# Script 4G (aba 05) — modelos

- `SCRIPT_4G_MG_SATELITE_6630.zip` (raiz do repositório): kit satélite de 2 setores usado pela aba 05.
- `SCRIPT_MODELO_4G_6630.zip` (raiz do repositório): modelo macro 6630 (setores A/B/C e I/J/K nas bandas 700/1800/2600, NB-IoT). O `7-ADD_EUtraNetwork&UtraNetwork.mos` e o `MME.mos` desse zip são da regional TNO.
- `regional/<REGIONAL>/`: `7-ADD_EUtraNetwork&UtraNetwork.mos` e `MME.mos` de cada regional (TLE, TNE, TNO).

A aba 05 lê a regional do site na ePD_MACRO_4G (coluna Regional) e usa os arquivos da regional:
- `EUtranFrequency.mos` e `MME.mos` do pacote saem com o conteúdo da regional;
- nas células, as relações `EUtranFreqRelation=LTE_n` / `eutranFrequencyRef …EUtranFrequency=LTE_n` (e as de WCDMA) seguem as frequências do EUtraNetwork&UtraNetwork da regional: as que existem ficam, as que faltam são criadas a partir da relação da mesma banda e as que não existem na regional saem;
- TLE é a regional do próprio kit: as células ficam como no modelo. Regional sem arquivo próprio usa os do kit (TLE) e avisa.

## Qual modelo a aba 05 usa

- **Automático:** site só com setores A/B (ou I/J) → satélite; site com setor C/K, NB-IoT (IA/IB/IC) → macro. Dá para forçar por site na coluna "Modelo".
- **Macro** monta o pacote pelas células da ePD:
  - equipamento por banda e só dos setores presentes: 2100 → `4/5/6-Equipamento_sector_1/2/3_2100` (RRU-20/22/24, AUG/SEF 21/22/23; RiPort A/B/C, ou G/H/J se o site também tiver 2600); 2600 → `4/5/6-Equipamento_sector_1/2/3_2600` (RRU-1/3/5); 1800 → `4-RRU_1800`, `5-AntennaUnitGroup_1800`, `7-SECTOR_1800` (RRU-17/19/21, AUG/SEF 9/10/11); 700 → `4-RRU_700`, `5-AntennaUnitGroup_700`, `7-SECTOR_700` (RRU/AUG/SEF 13/14/15);
  - `6-RILINK_RUS` refeito com os RRUs do site: 2600 → RiPort A/B/C, 1800 → D/E/F, 700 → K/L/M (RiLink = número do RRU) — conferir com o cabeamento;
  - células `<banda>-<setor>.LIMPO.mos` e NB-IoT `<banda>-I<setor>.mos`, com cellId, PCI, EARFCN, banda, TAC da ePD;
  - `7-ADD_EUtraNetwork&UtraNetwork` e `MME` da regional (sem arquivo da regional: os do macro, TNO). Na TNO as células ficam como no modelo.

- AntennaUnitGroup, RRU, SectorEquipmentFunction, RiLink e RiPort não se repetem entre as bandas do mesmo site; se repetirem (kit trocado), o site fica com erro e não entra no zip.
- Satélite só para site de 1 banda com setores A/B; mais de uma banda vai para o macro.
- Células 2100 (`21-A/B/C.LIMPO.mos`) vieram de site TNE (SAPT27), sem as relações de vizinhança.
