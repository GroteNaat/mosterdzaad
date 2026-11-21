class VaultLocation {
  const VaultLocation(this.kind, this.token, this.label);
  final String kind, token, label;
  Map<String, dynamic> toJson() => {
    'kind': kind,
    'token': token,
    'label': label,
  };
  factory VaultLocation.fromJson(Map<String, dynamic> j) => VaultLocation(
    j['kind'] as String,
    j['token'] as String,
    j['label'] as String,
  );
}

abstract interface class VaultFiles {
  VaultLocation get location;
  Future<List<String>> list(String directory);
  Future<String?> read(String name);
  Future<void> writeNew(String name, String contents);
  Future<void> makeDirectory(String name);
  Future<void> remove(String name);
}

void checkRelative(String name) {
  if (name.isEmpty ||
      name.startsWith('/') ||
      name.contains('\\') ||
      name
          .split('/')
          .any(
            (part) =>
                part.isEmpty ||
                part == '.' ||
                part == '..' ||
                part.contains(':'),
          )) {
    throw const FormatException('Ongeldige bestandsnaam.');
  }
}
