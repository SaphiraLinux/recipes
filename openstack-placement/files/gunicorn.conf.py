# Saphira: sanitize sys.argv for oslo.config before the app loads.
# gunicorn 26 removed --name and passes its own flags through, which
# placement's argument parser rejects (exit 2, workers respawn
# forever); worse, pointing --config at placement.conf makes gunicorn
# import an INI file as Python (SyntaxError, nothing serves).
# Loading this file via --config reduces argv to the program name so
# the app parser sees nothing it did not write itself.
import sys
sys.argv = ["gunicorn"]
