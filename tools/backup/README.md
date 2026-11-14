# Scripts de backup antes da atividade

Usados na aba **07 · Executar no OSS → Backup antes da atividade** da Ferramenta Ericsson RAN (index2.html).

| Script | Uso |
|---|---|
| BACKUP_TNE / TSP / TLE / TCO / TNO | sites 4G/5G (RadioNode) de cada regional |
| BACKUP_*_3G | sites 3G (RBS/WCDMA) de cada regional |
| BACKUP_DUS | DUS antigos (sem usuário/senha no nó) |

As senhas **não ficam neste repositório** (ele é público). Os scripts usam marcadores que o helper troca na hora da execução:

- `{{SENHA_NO}}` → senha do usuário `rbs` do nó (a que funcionou no site, da lista cadastrada na aba 07)
- `{{SENHA_OSS}}` → senha do seu usuário no servidor OSS (a mesma do login, guardada só na memória do helper)

Na saída e no log as senhas aparecem como `******`.
Para usar fora da ferramenta (colando no WinFiol), troque os marcadores pelas senhas antes.
