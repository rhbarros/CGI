# Script 4G (aba 05) — modelos

- `SCRIPT_4G_MG_SATELITE_6630.zip` (raiz do repositório): kit satélite de 2 setores usado pela aba 05.
- `SCRIPT_MODELO_4G_6630.zip` (raiz do repositório): modelo macro 6630 (setores A/B/C e I/J/K nas bandas 700/1800/2600, NB-IoT). O `7-ADD_EUtraNetwork&UtraNetwork.mos` e o `MME.mos` desse zip são da regional TNO.
- `regional/<REGIONAL>/`: `7-ADD_EUtraNetwork&UtraNetwork.mos` e `MME.mos` de cada regional (TLE, TNE, TNO).

A aba 05 lê a regional do site na ePD_MACRO_4G (coluna Regional) e usa os arquivos da regional:
- `EUtranFrequency.mos` e `MME.mos` do pacote saem com o conteúdo da regional;
- nas células, as relações `EUtranFreqRelation=LTE_n` / `eutranFrequencyRef …EUtranFrequency=LTE_n` (e as de WCDMA) seguem as frequências do EUtraNetwork&UtraNetwork da regional: as que existem ficam, as que faltam são criadas a partir da relação da mesma banda e as que não existem na regional saem;
- TLE é a regional do próprio kit: as células ficam como no modelo. Regional sem arquivo próprio usa os do kit (TLE) e avisa.
