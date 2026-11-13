/**
 * @OnlyCurrentDoc
 *
 * Histórico compartilhado — Ferramenta Ericsson RAN (index2.html)
 * Fica DENTRO de uma planilha Google (Extensões > Apps Script) e só acessa essa planilha.
 *   Aba "sites":     uma linha por site: id · atualizado em · updated(ms) · quem · resumo · conteúdo (em pedaços)
 *   Aba "log":       uma linha por gravação/exclusão: data/hora · ação · site · quem · EnderecoID · FRUs · células
 *   Aba "excluidos": sites apagados (para sumirem de todos os computadores)
 * Publicar: Implantar > Nova implantação > App da Web
 *   Executar como: Eu  ·  Quem pode acessar: Qualquer pessoa
 */
var ABA = 'sites', ABA_LOG = 'log', ABA_DEL = 'excluidos', PEDACO = 45000, COL_CONT = 6;
var CAB = {
  sites: ['Site', 'Atualizado em', 'updated (ms)', 'Quem', 'Resumo'],
  log: ['Data/hora', 'Ação', 'Site', 'Quem', 'EnderecoID', 'FRUs', 'Células'],
  excluidos: ['Site', 'Excluído (ms)', 'Quem']
};

function aba_(nome) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sh = ss.getSheetByName(nome);
  if (!sh) {
    sh = ss.insertSheet(nome);
    if (CAB[nome]) { sh.getRange(1, 1, 1, CAB[nome].length).setValues([CAB[nome]]).setFontWeight('bold'); sh.setFrozenRows(1); }
  }
  return sh;
}
// textos gravados com "_" na frente para a planilha não converter em número, data ou fórmula
function txt_(v) { return String(v).replace(/^_/, ''); }
function quando_(ms) { return Utilities.formatDate(new Date(Number(ms) || Date.now()), 'America/Fortaleza', 'dd/MM/yyyy HH:mm:ss'); }
function linhas_(sh, cols) { var n = sh.getLastRow(); return n > 1 ? sh.getRange(2, 1, n - 1, cols).getValues() : []; }
function acha_(sh, id) {
  var v = linhas_(sh, 1);
  for (var i = 0; i < v.length; i++) if (String(v[i][0]) === String(id)) return i + 2;
  return 0;
}
function indice_() {
  var sites = linhas_(aba_(ABA), 5).filter(function (r) { return r[0] !== ''; })
    .map(function (r) { return JSON.parse(txt_(r[4])); });
  var del = {};
  linhas_(aba_(ABA_DEL), 2).forEach(function (r) { if (r[0] !== '') del[r[0]] = Number(r[1]); });
  return { sites: sites, deleted: del };
}
function lerSite_(id) {
  var sh = aba_(ABA), r = acha_(sh, id);
  if (!r) return null;
  var w = sh.getLastColumn();
  if (w < COL_CONT) return null;
  var partes = sh.getRange(r, COL_CONT, 1, w - COL_CONT + 1).getValues()[0].filter(function (v) { return v !== ''; }).map(txt_);
  return JSON.parse(partes.join(''));
}
function gravarSite_(s, resumo) {
  var sh = aba_(ABA), r = acha_(sh, s.node) || sh.getLastRow() + 1;
  var t = JSON.stringify(s), partes = [];
  for (var i = 0; i < t.length; i += PEDACO) partes.push('_' + t.substr(i, PEDACO));
  var precisa = COL_CONT - 1 + partes.length;
  if (sh.getMaxColumns() < precisa) sh.insertColumnsAfter(sh.getMaxColumns(), precisa - sh.getMaxColumns());
  var w = sh.getLastColumn();
  if (w >= COL_CONT) sh.getRange(r, COL_CONT, 1, w - COL_CONT + 1).clearContent();
  sh.getRange(r, 1, 1, 5).setValues([[s.node, quando_(s.updated), s.updated || 0, s.by || '', '_' + JSON.stringify(resumo)]]);
  sh.getRange(r, COL_CONT, 1, partes.length).setValues([partes]);
}
function log_(acao, id, quem, resumo) {
  resumo = resumo || {};
  aba_(ABA_LOG).appendRow([quando_(Date.now()), acao, id, quem || '', resumo.enderecoId || '', resumo.frus || '', resumo.cells || '']);
}
function tirarExcluido_(id) { var d = aba_(ABA_DEL), r = acha_(d, id); if (r) d.deleteRow(r); }
function saida_(o) { return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON); }

// Leitura: ?a=index (lista) ou ?a=get&id=4G-XXXX (site completo)
function doGet(e) {
  try {
    var p = (e && e.parameter) || {};
    if (p.a === 'get') {
      var site = lerSite_(p.id);
      return saida_(site ? { ok: true, site: site } : { ok: false, erro: 'site não encontrado no histórico compartilhado' });
    }
    return saida_({ ok: true, index: indice_() });
  } catch (err) {
    return saida_({ ok: false, erro: String(err) });
  }
}

// Gravação: { a: "put", site, resumo }  ou  { a: "del", id, by }
function doPost(e) {
  var lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    var d = JSON.parse(e.postData.contents);
    if (d.a === 'put') {
      var s = d.site;
      if (!s || !s.node) throw new Error('site sem node');
      var sh = aba_(ABA), r = acha_(sh, s.node);
      var atual = r ? Number(sh.getRange(r, 3).getValue()) : 0;
      if (!r || (s.updated || 0) > atual) {
        gravarSite_(s, d.resumo);
        tirarExcluido_(s.node);
        log_(r ? 'atualizado' : 'novo', s.node, s.by, d.resumo);
      }
    } else if (d.a === 'del') {
      var sh2 = aba_(ABA), r2 = acha_(sh2, d.id);
      if (r2) sh2.deleteRow(r2);
      tirarExcluido_(d.id);
      aba_(ABA_DEL).appendRow([d.id, Date.now(), d.by || '']);
      log_('excluído', d.id, d.by);
    } else {
      throw new Error('ação desconhecida');
    }
    return saida_({ ok: true, index: indice_() });
  } catch (err) {
    return saida_({ ok: false, erro: String(err) });
  } finally {
    lock.releaseLock();
  }
}
