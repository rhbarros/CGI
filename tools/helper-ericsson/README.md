# Helper Ericsson (aba 07 · Executar no OSS)

Ponte entre a Ferramenta Ericsson RAN (index2.html) e o servidor do OSS, para rodar AMOS no nó pelo navegador:

```
index2.html --HTTP--> helper no PC (127.0.0.1:8766) --SSH (porta 5022)--> servidor OSS --> amos <nó>
```

- Instalar: na aba 07, botão **Instalar neste PC (1ª vez)** (baixa `tools/Instalar_Helper_Ericsson.bat`). Ele instala Python e paramiko se faltar, copia o helper para `%LOCALAPPDATA%\Ericsson_Helper` e o põe para iniciar com o Windows, sem janela. Remover: `Instalar_Helper_Ericsson.bat remover`.
- Usuário e senha vão só para o helper e ficam apenas na memória dele. Os IPs dos servidores ficam só no navegador de cada um (não estão neste repositório).
- O helper só atende esta página (rhbarros.github.io), localhost e o arquivo aberto do disco.
- Comandos de alteração (set, crn, del, bl, deb, acc, run…) exigem confirmação na página; perguntas [y/n] do AMOS são respondidas pelo usuário.
- Scripts .mos são gravados em `~/.enmhelper/` no servidor e rodados com `run`.

Depois de mexer no helper: `python gerar_instalador.py` e copie o `.bat` gerado para `tools/`.
