'use strict';
// UAM Virtual para Nintendo 2DS/3DS.
// El navegador de la consola es un WebKit de 2011: sin JS moderno, sin CORS,
// TLS viejo. Por eso TODO se renderiza acá en el servidor como HTML plano y
// este proceso es quien habla con Moodle (mismo web service que la app de Mac).

const INSTANCES = {
  grado: { name: 'Grado', url: 'https://uamvirtual.uam.edu.ni/grado/' },
  lc: { name: 'Language Center', url: 'https://uamvirtual.uam.edu.ni/lc/' },
  posgrado: { name: 'Posgrado', url: 'https://uamvirtualposgrado.uam.edu.ni/' }
};
const SERVICE = 'moodle_mobile_app';
const TZ = 'America/Managua';

// ---------- utilidades ----------
const esc = (s) => String(s == null ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const ENT = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };
function strip(html) {
  return String(html || '')
    .replace(/<(br|\/p|\/div|\/li|\/h\d)\s*\/?>/gi, '\n')
    .replace(/<li[^>]*>/gi, '- ')
    .replace(/<[^>]+>/g, '')
    .replace(/&(#x?[0-9a-f]+|[a-z]+);/gi, (m, e) => {
      if (e[0] === '#') {
        const n = e[1].toLowerCase() === 'x' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
        return n ? String.fromCodePoint(n) : m;
      }
      return ENT[e.toLowerCase()] || m;
    })
    .replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
}
const text = (s, max) => {
  let t = esc(strip(s)).replace(/\n/g, '<br>');
  if (max && t.length > max) t = t.slice(0, max) + '…';
  return t;
};
const fmtDate = (ts) => ts
  ? new Date(ts * 1000).toLocaleString('es-NI', { timeZone: TZ, day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
  : '—';
const fmtDay = (ts) => new Date(ts * 1000).toLocaleDateString('es-NI', { timeZone: TZ, weekday: 'short', day: 'numeric', month: 'short' });
const size = (b) => !b ? '' : b > 1048576 ? (b / 1048576).toFixed(1) + ' MB' : Math.ceil(b / 1024) + ' KB';
const num = (v, d) => { const n = parseInt(v, 10); return isNaN(n) ? d : n; };

class MoodleError extends Error {
  constructor(message, code) { super(message); this.code = code; }
}

function flat(obj, prefix, out) {
  out = out || {};
  for (const k of Object.keys(obj)) {
    const key = prefix ? prefix + '[' + k + ']' : k;
    const v = obj[k];
    if (v !== null && typeof v === 'object') flat(v, key, out);
    else if (v !== undefined && v !== null) out[key] = String(v);
  }
  return out;
}
const form = (o) => Object.keys(o).map((k) => encodeURIComponent(k) + '=' + encodeURIComponent(o[k])).join('&');

async function post(url, fields) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 55000); // el servidor de la UAM es lento
  try {
    const r = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8', Accept: 'application/json' },
      body: form(fields),
      signal: ctl.signal
    });
    const raw = await r.text();
    try { return JSON.parse(raw); }
    catch (e) { throw new MoodleError('Moodle no respondió JSON (HTTP ' + r.status + ').', 'not_json'); }
  } catch (e) {
    if (e instanceof MoodleError) throw e;
    throw new MoodleError(e.name === 'AbortError' ? 'Moodle tardó demasiado.' : 'No se pudo contactar a Moodle.', 'network');
  } finally { clearTimeout(timer); }
}

async function login(inst, cif, pin) {
  const base = INSTANCES[inst].url;
  const r = await post(base + 'login/token.php', { username: cif, password: pin, service: SERVICE });
  if (!r.token) throw new MoodleError(r.error || 'Moodle no devolvió token.', r.errorcode);
  return r.token;
}

function client(sess) {
  const base = INSTANCES[sess.inst].url;
  return {
    base,
    async call(fn, params) {
      const r = await post(base + 'webservice/rest/server.php',
        Object.assign({ wstoken: sess.token, wsfunction: fn, moodlewsrestformat: 'json' }, flat(params || {})));
      if (r && r.exception) throw new MoodleError(r.message || r.exception, r.errorcode);
      return r;
    },
    withToken(u) { return u + (u.indexOf('?') < 0 ? '?' : '&') + 'token=' + encodeURIComponent(sess.token); }
  };
}

// ---------- sesión (cookie) ----------
function parseCookies(h) {
  const o = {};
  String(h || '').split(';').forEach((p) => {
    const i = p.indexOf('=');
    if (i > 0) o[p.slice(0, i).trim()] = p.slice(i + 1).trim();
  });
  return o;
}
function getSession(req, q) {
  const c = parseCookies(req.headers.cookie).s || (q && q.s);
  if (!c) return null;
  const p = c.split('.');
  if (p.length !== 3 || !INSTANCES[p[0]] || !/^[0-9a-f]+$/i.test(p[1]) || !/^\d+$/.test(p[2])) return null;
  return { inst: p[0], token: p[1], uid: +p[2] };
}
function cookie(req, value, maxAge) {
  const https = (req.headers['x-forwarded-proto'] || '').indexOf('https') === 0;
  // Sin SameSite/Max-Age: el WebKit de la 2DS los ignora o rompe; Expires sí lo entiende.
  return 's=' + value + '; Path=/; Expires=' + new Date(Date.now() + maxAge * 1000).toUTCString() + (https ? '; Secure' : '');
}

// ---------- vistas ----------
// Degradado con las tres sintaxis que entiende el WebKit de 2011 (y uno sólido de respaldo).
const g = (a, b) => 'background:' + a + ';background:-webkit-gradient(linear,0 0,0 100%,from(' + a + '),to(' + b + '));' +
  'background:-webkit-linear-gradient(top,' + a + ',' + b + ');background:linear-gradient(' + a + ',' + b + ');';
// Brillo "Aero/Wii": mitad superior clara, corte duro a la mitad.
const gloss = (a, b, c, d) => 'background:' + c + ';background:-webkit-gradient(linear,0 0,0 100%,from(' + a + '),color-stop(.5,' + b + '),color-stop(.5,' + c + '),to(' + d + '));' +
  'background:-webkit-linear-gradient(top,' + a + ',' + b + ' 50%,' + c + ' 50%,' + d + ');background:linear-gradient(' + a + ',' + b + ' 50%,' + c + ' 50%,' + d + ');';
const R = (r) => '-webkit-border-radius:' + r + ';border-radius:' + r + ';';
const SH = (v) => '-webkit-box-shadow:' + v + ';box-shadow:' + v + ';';

const CSS = 'html{background:#dcdfe4}body{min-height:230px;margin:0;padding:0 5px 8px;color:#222;font:15px/1.35 sans-serif;' + g('#fdfdfd', '#dcdfe4') + '}' +
  '.bar{margin:0 -5px 6px;padding:5px 6px 4px;border-bottom:1px solid #4a0c17;' + gloss('#c4475a', '#a3243a', '#8b1a2b', '#6d1220') + SH('0 2px 4px rgba(0,0,0,.35)') + '}' +
  '.bar span{color:#fff;font-weight:bold;font-size:13px;text-shadow:0 1px 1px #000;letter-spacing:1px}' +
  '.top{margin:0 0 6px;padding:3px;border:1px solid #b7bcc4;' + R('9px') + g('#ffffff', '#e4e7ec') + SH('inset 0 1px 0 #fff') + '}' +
  '.top a{display:inline-block;padding:6px 9px;margin:1px;color:#5a1020;font-size:13px;font-weight:bold;text-decoration:none;border:1px solid #c9ccd2;text-shadow:0 1px 0 #fff;' + R('7px') + g('#ffffff', '#e9ebef') + '}' +
  'h1{font-size:18px;margin:2px 0 8px;padding:8px 10px;color:#fff;text-shadow:0 -1px 0 #3d0710;border:1px solid #5c0f1b;' + R('10px') + gloss('#b23a4e', '#962036', '#7e1627', '#9a2238') + SH('0 2px 3px rgba(0,0,0,.3),inset 0 1px 0 rgba(255,255,255,.4)') + '}' +
  'h2{font-size:14px;margin:12px 0 5px;padding:3px 8px;color:#fff;text-shadow:0 1px 0 #000;' + R('6px') + g('#7b8494', '#555d6b') + '}' +
  'a{color:#0a4fb4}' +
  '.nav a,.btn{display:block;margin:6px 0;padding:11px 8px;font-weight:bold;text-decoration:none;text-align:center;color:#6d1220;text-shadow:0 1px 0 #fff;border:1px solid #aab0b9;' + R('12px') + gloss('#ffffff', '#f3f4f6', '#e6e8ec', '#f4f5f7') + SH('0 2px 3px rgba(0,0,0,.25)') + '}' +
  '.nav a:active,.btn:active{' + g('#d7dbe1', '#f5f6f8') + '}' +
  '.row{margin:6px 0;padding:7px 8px;background:#fff;border:1px solid #c5c9cf;border-left:5px solid #8b1a2b;' + R('8px') + SH('0 1px 2px rgba(0,0,0,.18)') + '}.row b{display:block;color:#3a0a12}' +
  '.m{color:#6b7280;font-size:12px}' +
  '.err,.ok{padding:8px;font-weight:bold;' + R('8px') + '}.err{color:#7a0010;border:1px solid #d6545e;' + g('#ffe9eb', '#ffc9ce') + '}.ok{color:#0b5a17;border:1px solid #5ab567;' + g('#eafbe8', '#c8f0c4') + '}' +
  'label{display:block;margin-top:6px;font-weight:bold;font-size:13px;color:#444}' +
  'input,select,textarea{width:94%;font-size:16px;margin:3px 0;padding:6px;border:1px solid #9aa1ab;background:#fff;' + R('6px') + SH('inset 0 1px 2px rgba(0,0,0,.15)') + '}' +
  'input[type=submit]{width:100%;margin-top:8px;padding:11px;color:#fff;font-weight:bold;text-shadow:0 -1px 0 #3d0710;border:1px solid #5c0f1b;' + R('12px') + gloss('#c4475a', '#a3243a', '#8b1a2b', '#a12538') + SH('0 2px 3px rgba(0,0,0,.3)') + '}' +
  '.foot{margin-top:12px;text-align:center;color:#8a8f98;font-size:11px;text-shadow:0 1px 0 #fff}';

function page(title, body, sess) {
  const top = '<div class="top"><a href="/">Inicio</a><a href="/courses">Cursos</a><a href="/msgs">Mensajes</a>' +
    (sess ? '<a href="/logout">Salir</a>' : '') + '</div>';
  return '<!DOCTYPE html><html lang="es"><head><meta charset="utf-8"><title>' + esc(title) + '</title>' +
    '<meta name="viewport" content="width=320"><style>' + CSS + '</style></head><body>' +
    '<div class="bar"><span>UAM VIRTUAL</span></div>' + (sess ? top : '') + '<h1>' + esc(title) + '</h1>' + body +
    '<div class="foot">Universidad Americana &middot; edición 2DS</div></body></html>';
}
const row = (inner) => '<div class="row">' + inner + '</div>';
const link = (href, label) => '<a href="' + esc(href) + '">' + esc(label) + '</a>';
const none = (m) => '<p class="m">' + esc(m || 'Nada por aquí.') + '</p>';
const msg = (q) => q.ok ? '<p class="ok">' + esc(q.ok) + '</p>' : q.err ? '<p class="err">' + esc(q.err) + '</p>' : '';

function loginPage(err) {
  const opts = Object.keys(INSTANCES).map((k) => '<option value="' + k + '">' + esc(INSTANCES[k].name) + '</option>').join('');
  return page('UAM Virtual',
    (err ? '<p class="err">' + esc(err) + '</p>' : '') +
    '<form method="post" action="/login"><label>Sede</label><select name="inst">' + opts + '</select>' +
    '<label>CIF</label><input name="cif" autocapitalize="off" autocomplete="off">' +
    '<label>PIN</label><input name="pin" type="password"><input type="submit" value="Entrar"></form>' +
    '<p class="m">Tu PIN solo se usa para pedir el token a Moodle; en la cookie queda el token, no el PIN.</p>', null);
}

// ---------- rutas ----------
const routes = {};

routes['/'] = async (c) => {
  const [info, unread] = await Promise.all([
    c.call('core_webservice_get_site_info'),
    c.call('core_message_get_unread_conversations_count', { useridto: c.uid }).catch(() => null)
  ]);
  const n = unread && (unread.count != null ? unread.count : unread);
  return page(info.fullname,
    msg(c.q) + '<p class="m">' + esc(info.sitename) + (info.release ? ' · Moodle ' + esc(info.release) : '') + '</p>' +
    '<div class="nav">' +
    link('/courses', 'Mis cursos') + link('/assigns', 'Tareas pendientes') + link('/grades', 'Calificaciones') +
    link('/quizzes', 'Cuestionarios') + link('/calendar', 'Calendario') +
    link('/msgs', 'Mensajes' + (typeof n === 'number' && n > 0 ? ' (' + n + ' sin leer)' : '')) +
    link('/notifs', 'Notificaciones') + link('/search', 'Buscar') +
    link('/profile', 'Mi perfil') + '</div>', c.sess);
};

async function myCourses(c) {
  const list = await c.call('core_enrol_get_users_courses', { userid: c.uid });
  return list.filter((x) => !x.hidden);
}

routes['/courses'] = async (c) => {
  const cs = await myCourses(c);
  return page('Mis cursos', cs.length ? cs.map((x) => row(
    '<b>' + esc(x.fullname) + '</b>' +
    (x.progress != null ? '<span class="m">Avance: ' + Math.round(x.progress) + '%</span><br>' : '') +
    link('/course?id=' + x.id, 'Contenido') + ' · ' + link('/grades?id=' + x.id, 'Notas') + ' · ' +
    link('/forums?id=' + x.id, 'Foros') + ' · ' + link('/people?id=' + x.id, 'Participantes'))).join('') : none(), c.sess);
};

routes['/course'] = async (c) => {
  const id = num(c.q.id);
  const secs = await c.call('core_course_get_contents', { courseid: id, options: [{ name: 'includestealthmodules', value: 1 }] });
  const body = secs.map((s) => {
    const mods = (s.modules || []).filter((m) => m.uservisible !== false).map((m) => {
      let h = '<b>' + esc(m.name) + '</b><span class="m">' + esc(m.modname) + '</span>';
      if (m.description) h += '<br>' + text(m.description, 300);
      const open = m.modname === 'forum' ? link('/forum?id=' + m.instance + '&course=' + id, 'Abrir foro')
        : m.modname === 'assign' ? link('/assign?id=' + m.instance, 'Abrir tarea')
        : m.modname === 'quiz' ? link('/quiz?id=' + m.instance, 'Abrir cuestionario') : '';
      if (open) h += '<br>' + open;
      (m.contents || []).forEach((f) => {
        if (f.type === 'file') h += '<br>' + link('/file?u=' + encodeURIComponent(f.fileurl), f.filename) + ' <span class="m">' + size(f.filesize) + '</span>';
        else if (f.type === 'url') h += '<br>' + link('/file?u=' + encodeURIComponent(f.fileurl), 'Abrir enlace');
      });
      if (m.url && !open && !(m.contents || []).length) h += '<br>' + link('/file?u=' + encodeURIComponent(m.url), 'Abrir en Moodle');
      return row(h);
    }).join('');
    return (mods || s.summary) ? '<h2>' + esc(s.name) + '</h2>' + (s.summary ? '<p class="m">' + text(s.summary, 300) + '</p>' : '') + mods : '';
  }).join('');
  return page('Contenido', body || none(), c.sess);
};

// Descargas/enlaces: se redirige a Moodle con el token. Solo hosts de la UAM.
routes['/file'] = async (c) => {
  let u;
  try { u = new URL(c.q.u); } catch (e) { throw new MoodleError('Enlace inválido.'); }
  const ok = u.protocol === 'https:' && /(^|\.)uam\.edu\.ni$/.test(u.hostname);
  if (!ok) return { redirect: c.q.u }; // enlace externo (mod url)
  return { redirect: c.withToken(c.q.u.replace('/webservice/pluginfile.php', '/webservice/pluginfile.php')) };
};

routes['/assigns'] = async (c) => {
  const cs = await myCourses(c);
  const r = await c.call('mod_assign_get_assignments', { courseids: cs.map((x) => x.id) });
  const all = [];
  (r.courses || []).forEach((k) => (k.assignments || []).forEach((a) => all.push({ a, course: k.shortname || k.fullname })));
  const now = Date.now() / 1000;
  const fut = all.filter((x) => !x.a.duedate || x.a.duedate >= now).sort((p, q) => (p.a.duedate || 9e12) - (q.a.duedate || 9e12));
  const past = all.filter((x) => x.a.duedate && x.a.duedate < now).sort((p, q) => q.a.duedate - p.a.duedate).slice(0, 15);
  const show = (x) => row('<b>' + link('/assign?id=' + x.a.id, x.a.name) + '</b><span class="m">' + esc(x.course) + ' · vence ' + fmtDate(x.a.duedate) + '</span>');
  return page('Tareas', '<h2>Próximas</h2>' + (fut.map(show).join('') || none()) + '<h2>Vencidas (recientes)</h2>' + (past.map(show).join('') || none()), c.sess);
};

routes['/assign'] = async (c) => {
  const id = num(c.q.id);
  const [st, cs] = await Promise.all([c.call('mod_assign_get_submission_status', { assignid: id }), myCourses(c)]);
  const r = await c.call('mod_assign_get_assignments', { courseids: cs.map((x) => x.id) });
  let a = null;
  (r.courses || []).forEach((k) => (k.assignments || []).forEach((x) => { if (x.id === id) a = x; }));
  const sub = st.lastattempt && st.lastattempt.submission;
  const fb = st.feedback;
  let h = msg(c.q) + (a ? row('<b>' + esc(a.name) + '</b><span class="m">Vence ' + fmtDate(a.duedate) + '</span><br>' + text(a.intro, 1500)) : '');
  if (a) (a.introattachments || []).forEach((f) => { h += row(link('/file?u=' + encodeURIComponent(f.fileurl), f.filename) + ' <span class="m">' + size(f.filesize) + '</span>'); });
  h += row('<b>Estado:</b> ' + esc(sub ? sub.status : 'sin entrega') + '<br><b>Calificación:</b> ' + esc(st.lastattempt ? st.lastattempt.gradingstatus : '—') +
    (fb && fb.gradefordisplay ? '<br><b>Nota:</b> ' + esc(strip(fb.gradefordisplay)) : ''));
  const canEdit = st.lastattempt && st.lastattempt.canedit;
  if (canEdit) {
    h += '<h2>Entregar texto</h2><form method="post" action="/assign/save"><input type="hidden" name="id" value="' + id + '">' +
      '<textarea name="t" rows="6"></textarea><label><input type="checkbox" name="send" value="1" style="width:auto"> Enviar para calificar</label>' +
      '<input type="submit" value="Guardar entrega"></form><p class="m">Solo texto en línea. Archivos: usa la app o Moodle.</p>';
  }
  return page('Tarea', h, c.sess);
};

routes['POST /assign/save'] = async (c) => {
  const id = num(c.b.id);
  const w = await c.call('mod_assign_save_submission', {
    assignmentid: id,
    plugindata: { onlinetext_editor: { text: c.b.t || '', format: 1, itemid: 0 } }
  });
  if (Array.isArray(w) && w[0]) return { redirect: '/assign?id=' + id + '&err=' + encodeURIComponent(w[0].message || 'Moodle rechazó la entrega.') };
  if (c.b.send) {
    const w2 = await c.call('mod_assign_submit_for_grading', { assignmentid: id, acceptsubmissionstatement: 1 });
    if (Array.isArray(w2) && w2[0]) return { redirect: '/assign?id=' + id + '&err=' + encodeURIComponent(w2[0].message || 'No se pudo enviar.') };
  }
  return { redirect: '/assign?id=' + id + '&ok=' + encodeURIComponent(c.b.send ? 'Enviada para calificar.' : 'Borrador guardado.') };
};

routes['/grades'] = async (c) => {
  const id = num(c.q.id, 0);
  if (!id) {
    const cs = await myCourses(c);
    return page('Calificaciones', cs.map((x) => row('<b>' + link('/grades?id=' + x.id, x.fullname) + '</b>')).join('') || none(), c.sess);
  }
  const r = await c.call('gradereport_user_get_grade_items', { courseid: id, userid: c.uid });
  const items = ((r.usergrades || [])[0] || {}).gradeitems || [];
  return page('Notas', items.map((g) => row('<b>' + esc(g.itemname || 'Total del curso') + '</b><span class="m">' +
    esc(strip(g.gradeformatted || '-')) + ' / ' + esc(g.grademax != null ? g.grademax : '?') +
    (g.percentageformatted ? ' · ' + esc(g.percentageformatted) : '') + '</span>')).join('') || none(), c.sess);
};

routes['/quizzes'] = async (c) => {
  const cs = await myCourses(c);
  const r = await c.call('mod_quiz_get_quizzes_by_courses', { courseids: cs.map((x) => x.id) });
  return page('Cuestionarios', (r.quizzes || []).map((q) => row('<b>' + link('/quiz?id=' + q.id, q.name) + '</b><span class="m">Cierra ' + fmtDate(q.timeclose) + '</span>')).join('') || none(), c.sess);
};

routes['/quiz'] = async (c) => {
  const id = num(c.q.id);
  const [acc, att] = await Promise.all([
    c.call('mod_quiz_get_quiz_access_information', { quizid: id }).catch(() => ({})),
    c.call('mod_quiz_get_user_attempts', { quizid: id, userid: c.uid, status: 'all', includepreviews: 0 })
  ]);
  const msgs = (acc.preventnewattemptreasons || []).map((m) => '<li>' + esc(strip(m)) + '</li>').join('');
  const rows = (att.attempts || []).map((a) => row('<b>Intento ' + a.attempt + '</b> · ' + esc(a.state) +
    '<br><span class="m">' + fmtDate(a.timestart) + ' → ' + fmtDate(a.timefinish) + (a.sumgrades != null ? ' · puntaje ' + esc(a.sumgrades) : '') + '</span>')).join('');
  return page('Cuestionario',
    row(acc.canattempt ? 'Puedes intentar este cuestionario.' : 'No se puede iniciar un intento ahora.') +
    (msgs ? '<ul>' + msgs + '</ul>' : '') + '<h2>Intentos</h2>' + (rows || none()) +
    '<p class="m">Resolver el examen en la 2DS no está soportado a propósito: perder respuestas por un corte de red sería grave.</p>', c.sess);
};

routes['/forums'] = async (c) => {
  const id = num(c.q.id);
  const fs = await c.call('mod_forum_get_forums_by_courses', { courseids: [id] });
  return page('Foros', fs.map((f) => row('<b>' + link('/forum?id=' + f.id + '&course=' + id, f.name) + '</b><span class="m">' + (f.numdiscussions != null ? f.numdiscussions + ' temas' : '') + '</span>')).join('') || none(), c.sess);
};

routes['/forum'] = async (c) => {
  const id = num(c.q.id), pg = num(c.q.p, 0);
  const r = await c.call('mod_forum_get_forum_discussions_paginated', { forumid: id, page: pg, perpage: 10 });
  const ds = r.discussions || [];
  const nav = (pg > 0 ? link('/forum?id=' + id + '&p=' + (pg - 1), '« Anteriores') + ' ' : '') + (ds.length === 10 ? link('/forum?id=' + id + '&p=' + (pg + 1), 'Siguientes »') : '');
  return page('Foro', msg(c.q) + ds.map((d) => row('<b>' + link('/disc?id=' + d.discussion, d.name || d.subject) + '</b><span class="m">' +
    esc(d.userfullname) + ' · ' + fmtDate(d.timemodified) + ' · ' + (d.numreplies || 0) + ' resp.</span>')).join('') + (nav ? '<p>' + nav + '</p>' : '') || none(), c.sess);
};

routes['/disc'] = async (c) => {
  const id = num(c.q.id);
  const r = await c.call('mod_forum_get_discussion_posts', { discussionid: id });
  const posts = r.posts || [];
  const first = posts.filter((p) => !p.parentid && !p.parent)[0] || posts[0];
  const body = posts.map((p) => row('<b>' + esc(p.subject) + '</b><span class="m">' +
    esc((p.author && p.author.fullname) || p.userfullname) + ' · ' + fmtDate(p.timecreated) + '</span><br>' + text(p.message, 2500))).join('');
  return page('Tema', msg(c.q) + body + (first ? '<h2>Responder</h2><form method="post" action="/disc/reply"><input type="hidden" name="id" value="' + id + '">' +
    '<input type="hidden" name="post" value="' + first.id + '"><input type="hidden" name="s" value="' + esc('Re: ' + first.subject) + '">' +
    '<textarea name="m" rows="5"></textarea><input type="submit" value="Publicar respuesta"></form>' : ''), c.sess);
};

routes['POST /disc/reply'] = async (c) => {
  const id = num(c.b.id);
  if (!String(c.b.m || '').trim()) return { redirect: '/disc?id=' + id + '&err=' + encodeURIComponent('Escribe algo primero.') };
  await c.call('mod_forum_add_discussion_post', { postid: num(c.b.post), subject: c.b.s || 'Re:', message: c.b.m, messageformat: 1 });
  return { redirect: '/disc?id=' + id + '&ok=' + encodeURIComponent('Respuesta publicada.') };
};

routes['/msgs'] = async (c) => {
  const r = await c.call('core_message_get_conversations', { userid: c.uid, limitfrom: 0, limitnum: 30, favourites: 0 });
  const cv = r.conversations || [];
  return page('Mensajes', '<div class="nav">' + link('/people?find=1', 'Escribir a alguien') + '</div>' + (cv.map((x) => {
    const last = (x.messages || [])[0];
    return row('<b>' + link('/conv?id=' + x.id, x.name || 'Conversación') + (x.unreadcount ? ' (' + x.unreadcount + ')' : '') + '</b>' +
      (last ? '<span class="m">' + text(last.text, 90) + '</span>' : ''));
  }).join('') || none()), c.sess);
};

routes['/conv'] = async (c) => {
  const id = num(c.q.id);
  const r = await c.call('core_message_get_conversation_messages', { currentuserid: c.uid, convid: id, limitfrom: 0, limitnum: 30, newest: 1 });
  const names = {};
  (r.members || []).forEach((m) => { names[m.id] = m.fullname; });
  const ms = (r.messages || []).slice().sort((a, b) => a.timecreated - b.timecreated);
  return page(r.name || 'Conversación', msg(c.q) + (ms.map((m) => row('<b>' + esc(m.useridfrom === c.uid ? 'Yo' : names[m.useridfrom] || 'Otro') + '</b><span class="m">' + fmtDate(m.timecreated) + '</span><br>' + text(m.text, 1500))).join('') || none()) +
    '<form method="post" action="/conv/send"><input type="hidden" name="id" value="' + id + '"><textarea name="m" rows="3"></textarea><input type="submit" value="Enviar"></form>', c.sess);
};

routes['POST /conv/send'] = async (c) => {
  const id = num(c.b.id);
  if (String(c.b.m || '').trim()) await c.call('core_message_send_messages_to_conversation', { conversationid: id, messages: [{ text: c.b.m, textformat: 1 }] });
  return { redirect: '/conv?id=' + id };
};

routes['/notifs'] = async (c) => {
  const r = await c.call('message_popup_get_popup_notifications', { useridto: c.uid, newestfirst: 1, limit: 25, offset: 0 });
  return page('Notificaciones', (r.notifications || []).map((n) => row('<b>' + esc(n.subject) + '</b><span class="m">' + fmtDate(n.timecreated) + '</span><br>' + text(n.smallmessage || n.fullmessage, 200))).join('') || none(), c.sess);
};

routes['/calendar'] = async (c) => {
  const now = new Date();
  const y = num(c.q.y, now.getFullYear()), m = num(c.q.m, now.getMonth() + 1);
  const r = await c.call('core_calendar_get_calendar_monthly_view', { year: y, month: m, courseid: 0, categoryid: 0, includenavigation: 1, mini: 0 });
  const pm = m === 1 ? [y - 1, 12] : [y, m - 1], nm = m === 12 ? [y + 1, 1] : [y, m + 1];
  const evs = [];
  (r.weeks || []).forEach((w) => (w.days || []).forEach((d) => (d.events || []).forEach((e) => evs.push(e))));
  evs.sort((a, b) => a.timestart - b.timestart);
  return page('Calendario ' + m + '/' + y,
    '<p>' + link('/calendar?y=' + pm[0] + '&m=' + pm[1], '« Anterior') + ' ' + link('/calendar?y=' + nm[0] + '&m=' + nm[1], 'Siguiente »') + '</p>' +
    (evs.map((e) => row('<b>' + esc(e.name) + '</b><span class="m">' + fmtDay(e.timestart) + ' ' + fmtDate(e.timestart).split(', ').pop() + (e.course ? ' · ' + esc(e.course.shortname || e.course.fullname) : '') + '</span>')).join('') || none('Sin eventos.')), c.sess);
};

routes['/people'] = async (c) => {
  if (c.q.find) {
    return page('Buscar persona', '<form method="get" action="/people"><input name="q" placeholder="Nombre"><input type="submit" value="Buscar"></form>', c.sess);
  }
  if (c.q.q) {
    const r = await c.call('core_message_search_users', { userid: c.uid, search: c.q.q, limitnum: 20 });
    const us = (r.noncontacts || []).concat(r.contacts || []);
    return page('Resultados', us.map((u) => row('<b>' + esc(u.fullname) + '</b>' + link('/chat?to=' + u.id, 'Mensaje') + ' · ' + link('/user?id=' + u.id, 'Perfil'))).join('') || none(), c.sess);
  }
  const us = await c.call('core_enrol_get_enrolled_users', { courseid: num(c.q.id), options: [{ name: 'limitnumber', value: 60 }] });
  return page('Participantes', us.map((u) => row('<b>' + link('/user?id=' + u.id, u.fullname) + '</b>' + (u.roles && u.roles.length ? '<span class="m">' + esc(u.roles.map((r) => r.shortname).join(', ')) + '</span>' : ''))).join('') || none(), c.sess);
};

routes['/chat'] = async (c) => {
  const r = await c.call('core_message_get_conversation_between_users', { userid: c.uid, otheruserid: num(c.q.to), includecontactrequests: 0, includeprivacyinfo: 0 }).catch(() => null);
  if (r && r.id) return { redirect: '/conv?id=' + r.id };
  return page('Nuevo mensaje', '<form method="post" action="/chat/send"><input type="hidden" name="to" value="' + num(c.q.to) + '"><textarea name="m" rows="4"></textarea><input type="submit" value="Enviar"></form>', c.sess);
};
routes['POST /chat/send'] = async (c) => {
  await c.call('core_message_send_instant_messages', { messages: [{ touserid: num(c.b.to), text: c.b.m || '', textformat: 1 }] });
  return { redirect: '/msgs' };
};

routes['/user'] = async (c) => {
  const r = await c.call('core_user_get_users_by_field', { field: 'id', values: [num(c.q.id)] });
  const u = r[0];
  if (!u) return page('Perfil', none('No encontrado.'), c.sess);
  return page(u.fullname, row((u.email ? 'Correo: ' + esc(u.email) + '<br>' : '') + (u.city ? esc(u.city) + '<br>' : '') +
    (u.description ? text(u.description, 800) : '') + '<br>' + link('/chat?to=' + u.id, 'Enviar mensaje')), c.sess);
};

routes['/profile'] = async (c) => {
  const i = await c.call('core_webservice_get_site_info');
  return page(i.fullname, row('Usuario: ' + esc(i.username) + '<br>Sitio: ' + esc(i.sitename) + '<br>ID: ' + i.userid) + '<div class="nav">' + link('/logout', 'Cerrar sesión') + '</div>', c.sess);
};

routes['/search'] = async (c) => {
  const q = String(c.q.q || '').trim();
  let out = '<form method="get" action="/search"><input name="q" value="' + esc(q) + '" placeholder="Buscar cursos"><input type="submit" value="Buscar"></form>';
  if (q) {
    const r = await c.call('core_course_search_courses', { criterianame: 'search', criteriavalue: q, page: 0, perpage: 15 });
    out += (r.courses || []).map((k) => row('<b>' + esc(k.fullname) + '</b><span class="m">' + esc(k.shortname) + '</span>')).join('') || none('Sin resultados.');
  }
  return page('Buscar', out, c.sess);
};

// ---------- servidor ----------
function readBody(req) {
  return new Promise((resolve) => {
    let d = '';
    req.on('data', (x) => { d += x; if (d.length > 200000) req.destroy(); });
    req.on('end', () => {
      const o = {};
      d.split('&').forEach((p) => {
        if (!p) return;
        const i = p.indexOf('=');
        const dec = (s) => { try { return decodeURIComponent(s.replace(/\+/g, ' ')); } catch (e) { return s; } };
        o[dec(i < 0 ? p : p.slice(0, i))] = i < 0 ? '' : dec(p.slice(i + 1));
      });
      resolve(o);
    });
  });
}

function send(res, code, body, headers) {
  res.writeHead(code, Object.assign({ 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' }, headers || {}));
  res.end(body);
}

async function handler(req, res) {
  try {
    const url = new URL(req.url, 'http://x');
    const path = url.pathname.replace(/\/+$/, '') || '/';
    const q = {};
    url.searchParams.forEach((v, k) => { q[k] = v; });

    if (path === '/health') return send(res, 200, 'ok', { 'Content-Type': 'text/plain' });

    if (path === '/login' && req.method === 'POST') {
      const b = await readBody(req);
      const inst = INSTANCES[b.inst] ? b.inst : 'grado';
      try {
        const token = await login(inst, String(b.cif || '').trim(), String(b.pin || ''));
        const info = await client({ inst, token }).call('core_webservice_get_site_info');
        const sv = inst + '.' + token + '.' + info.userid;
        return send(res, 302, '', { Location: '/?s=' + sv, 'Set-Cookie': cookie(req, sv, 2592000) });
      } catch (e) {
        return send(res, 200, loginPage(e.message));
      }
    }
    if (path === '/logout') return send(res, 302, '', { Location: '/', 'Set-Cookie': cookie(req, '', 0) });

    const sess = getSession(req, q);
    const viaUrl = sess && !parseCookies(req.headers.cookie).s;
    const sv = viaUrl ? q.s : null;
    const tag = (u) => u.replace(/^(\/(?!\/)[^#]*?)(#.*)?$/, (m, a, h) => a + (a.indexOf('?') < 0 ? '?' : '&') + 's=' + sv + (h || ''));
    if (!sess) return send(res, 200, loginPage());

    const key = req.method === 'POST' ? 'POST ' + path : path;
    const fn = routes[key];
    if (!fn) return send(res, 404, page('No existe', none('Esa página no existe.'), sess));

    const c = Object.assign(client(sess), { sess, uid: sess.uid, q, b: req.method === 'POST' ? await readBody(req) : {} });
    let out;
    try { out = await fn(c); }
    catch (e) {
      if (e instanceof MoodleError) {
        if (/token|accessexception|invalidtoken/i.test(e.code || '')) {
          return send(res, 200, loginPage('Tu sesión expiró. Entra de nuevo.'), { 'Set-Cookie': cookie(req, '', 0) });
        }
        return send(res, 200, page('Error', '<p class="err">' + esc(e.message) + '</p><p>' + link('javascript:history.back()', 'Volver') + '</p>', sess));
      }
      throw e;
    }
    if (out && out.redirect) return send(res, 302, '', { Location: sv && out.redirect[0] === '/' ? tag(out.redirect) : out.redirect });
    if (sv) {
      out = out.replace(/(href|action)="(\/[^"]*)"/g, (m, a, u) => a + '="' + tag(u.replace(/&amp;/g, '&')).replace(/&/g, '&amp;') + '"')
        .replace(/<form[^>]*>/g, (m) => m + '<input type="hidden" name="s" value="' + esc(sv) + '">');
    }
    return send(res, 200, out);
  } catch (e) {
    return send(res, 500, page('Error', '<p class="err">Fallo interno.</p>', null));
  }
}

module.exports = { handler };
