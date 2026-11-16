from .models import Preferences

def preferences(request):
    return {'preferences': Preferences.current()}
