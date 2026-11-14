# Gera Instalar_Helper_Ericsson.bat a partir de instalador_modelo.txt + ericsson_helper.py.
# Rode sempre que alterar o helper:  python gerar_instalador.py
import os
d = os.path.dirname(os.path.abspath(__file__))
modelo = open(os.path.join(d, "instalador_modelo.txt"), encoding="utf-8").read()
helper = open(os.path.join(d, "ericsson_helper.py"), encoding="utf-8").read().rstrip("\n")
assert "\n'@" not in helper, "o helper nao pode ter linha comecando com '@"
out = modelo.replace("__HELPER__", helper)
with open(os.path.join(d, "Instalar_Helper_Ericsson.bat"), "w", encoding="utf-8", newline="\r\n") as f:
    f.write(out)
print("ok:", len(out), "bytes")
