package nl.mosterdzaad.mosterdzaad

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import org.json.JSONObject
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private var pickerResult: MethodChannel.Result? = null
    private val io = Executors.newSingleThreadExecutor()
    private val requestCode = 7401

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nl.mosterdzaad/vault")
            .setMethodCallHandler { call, result ->
                if (call.method == "pickFolder") {
                    if (pickerResult != null) { result.error("busy", "Er staat al een mapkiezer open.", null); return@setMethodCallHandler }
                    pickerResult = result
                    try {
                        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                        }, requestCode)
                    } catch (e: Exception) { pickerResult = null; result.error("picker", e.localizedMessage, null) }
                } else {
                    io.execute {
                        try { val value = perform(call); runOnUiThread { result.success(value) } }
                        catch (e: Exception) { runOnUiThread { result.error("storage", "De gekozen map is niet toegankelijk: ${e.localizedMessage}", null) } }
                    }
                }
            }
    }

    @Deprecated("Uses the activity result bridge supported by FlutterActivity")
    override fun onActivityResult(request: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(request, resultCode, data)
        if (request != requestCode) return
        val result = pickerResult ?: return
        pickerResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) { result.success(null); return }
        try {
            val uri = data.data!!
            val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            require(flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION != 0) { "Deze locatie geeft geen schrijftoegang." }
            contentResolver.takePersistableUriPermission(uri, flags)
            val root = DocumentsContract.buildDocumentUriUsingTree(uri, DocumentsContract.getTreeDocumentId(uri))
            result.success(location(uri, DocumentsContract.getDocumentId(root), displayName(root)))
        } catch (e: Exception) { result.error("permission", e.localizedMessage, null) }
    }

    private fun location(tree: Uri, root: String, label: String) = mapOf("kind" to "android", "token" to JSONObject().put("tree", tree.toString()).put("root", root).toString(), "label" to label)
    private fun displayName(uri: Uri): String = contentResolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
        if (it.moveToFirst()) it.getString(0) else "Studieboek"
    } ?: "Studieboek"

    private fun children(tree: Uri, parent: Uri): List<Pair<String, Uri>> {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getDocumentId(parent))
        return contentResolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null)?.use { cursor ->
            buildList { while (cursor.moveToNext()) add(cursor.getString(0) to DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(1))) }
        } ?: throw IllegalStateException("De map kan niet worden gelezen.")
    }

    private fun perform(call: MethodCall): Any? {
        val token = call.argument<String>("token") ?: error("Locatie ontbreekt")
        val path = call.argument<String>("path") ?: error("Bestandsnaam ontbreekt")
        val parts = path.split('/')
        require(parts.all { it.isNotEmpty() && it != "." && it != ".." && !it.contains('\\') && !it.contains(':') }) { "Ongeldige bestandsnaam" }
        val locationData = JSONObject(token)
        val tree = Uri.parse(locationData.getString("tree"))
        require(tree.scheme == "content" && DocumentsContract.isTreeUri(tree)) { "Ongeldige mapverwijzing" }
        var parent = DocumentsContract.buildDocumentUriUsingTree(tree, locationData.getString("root"))
        for (part in parts.dropLast(1)) parent = children(tree, parent).firstOrNull { it.first == part }?.second ?: error("Map ontbreekt: $part")
        val name = parts.last()
        val existing = children(tree, parent).firstOrNull { it.first == name }?.second
        return when (call.method) {
            "createChild", "makeDirectory" -> {
                if (call.method == "createChild") require(existing == null) { "Deze map bestaat al." }
                val child = existing ?: DocumentsContract.createDocument(contentResolver, parent, DocumentsContract.Document.MIME_TYPE_DIR, name) ?: error("Map maken mislukt")
                if (call.method == "createChild") {
                    // Keep the original persisted tree grant and use its document ID as the root.
                    location(tree, DocumentsContract.getDocumentId(child), name)
                } else null
            }
            "list" -> children(tree, existing ?: error("Map ontbreekt")).map { it.first }
            "read" -> if (existing == null) null else contentResolver.openInputStream(existing)?.use {
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val count = it.read(buffer)
                    if (count < 0) break
                    require(output.size() + count <= 8 * 1024 * 1024) { "Bestand is te groot" }
                    output.write(buffer, 0, count)
                }
                output.toString("UTF-8")
            } ?: error("Lezen mislukt")
            "writeNew" -> {
                require(existing == null) { "Het bestand bestaat al; overschrijven is niet toegestaan." }
                val mime = if (name.endsWith(".md")) "text/markdown" else "application/json"
                val child = DocumentsContract.createDocument(contentResolver, parent, mime, name) ?: error("Bestand maken mislukt")
                require(displayName(child) == name) { "De provider veranderde de bestandsnaam." }
                contentResolver.openOutputStream(child, "wt")?.use { it.write((call.argument<String>("contents") ?: error("Inhoud ontbreekt")).toByteArray(Charsets.UTF_8)); it.flush() } ?: error("Schrijven mislukt")
                null
            }
            else -> error("Onbekende bestandsactie")
        }
    }
}
