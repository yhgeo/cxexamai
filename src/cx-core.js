/* CXExamAI 页面端核心
 * 职责：判定考试页 → 抓题 → 上报原生 → 接收答案回填 → DOM 事件伪装
 * 说明：注入时机为 documentStart，先于页面脚本执行
 */
(function () {
  if (window.__cxCore) return;
  window.__cxCore = 1;

  var H = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.cxNative;
  var URL_ = location.href;
  var SENT = {};        // 已上报过的题（stem hash）
  var Q = [];           // 当前页题目缓存
  var lastURL = URL_;

  function post(t, d) {
    try { H && H.postMessage({ t: t, d: d, u: location.href }); } catch (e) {}
  }

  // ---------- 站点判定 ----------
  function isExamPage() {
    var u = location.href;
    if (/\/(exam|exam-ans|reVersionTest|work)\b|examId=|examEnc=|workId=/i.test(u)) return true;
    var t = (document.title || '') + ' ' + ((document.body && document.body.innerText) || '').slice(0, 400);
    return /考试|测验|答题|单选题|多选题|判断题/.test(t) && /题|作答/.test(t);
  }
  function isFacePage() {
    return /face|verify|liveness|renzheng|certif/i.test(location.href);
  }

  // ---------- 反检测（仅考试页、非人脸页） ----------
  var GUARD = false;
  try {
    if (isExamPage() && !isFacePage()) {
      GUARD = true;
      try {
        Object.defineProperty(document, 'hidden', { get: function () { return false; }, configurable: false });
        Object.defineProperty(document, 'visibilityState', { get: function () { return 'visible'; }, configurable: false });
      } catch (e) {}
      try {
        var AEL = EventTarget.prototype.addEventListener;
        EventTarget.prototype.addEventListener = function (type, fn, opt) {
          if (this === document || this === window) {
            if (/^(visibilitychange|pagehide)$/i.test(type)) return;
          }
          return AEL.call(this, type, fn, opt);
        };
      } catch (e) {}
      try {
        Object.defineProperty(window, 'onblur', { get: function () { return null; }, set: function () {}, configurable: false });
        Object.defineProperty(window, 'onfocus', { get: function () { return null; }, set: function () {}, configurable: false });
        document.hasFocus = function () { return true; };
      } catch (e) {}
      post('log', 'guard on');
    }
  } catch (e) { post('log', 'guard fail ' + e); }

  // ---------- 文档集合（含同源 iframe） ----------
  function docs(root, depth) {
    var out = [root];
    if (depth <= 0) return out;
    var frames = root.querySelectorAll ? root.querySelectorAll('iframe') : [];
    for (var i = 0; i < frames.length; i++) {
      try {
        var d = frames[i].contentDocument;
        if (d) out = out.concat(docs(d, depth - 1));
      } catch (e) {}
    }
    return out;
  }

  var SEL = {
    block: ['.questionLi', '.TiMu', 'div[data-qid]', '.exam-question', '.queBox', '.subject'],
    stem: ['.Zy_TItle', '.stem', '.question-title', '.TiMu .title', '.mark_name', 'h3'],
    opt: ['ul.Zy_ulTop > li', 'li.option', 'label.option', '.answerList li', '.optionLi']
  };

  function txt(n) { return (n.innerText || n.textContent || '').replace(/\u00a0/g, ' ').replace(/\s+/g, ' ').trim(); }
  function hash(s) { var h = 5381; for (var i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0; return (h >>> 0).toString(36); }
  function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }

  function findBlocks() {
    var out = [], seen = [];
    docs(document, 3).forEach(function (doc) {
      SEL.block.forEach(function (sel) {
        var list = [];
        try { list = doc.querySelectorAll(sel); } catch (e) {}
        for (var i = 0; i < list.length; i++) {
          var n = list[i];
          if (seen.indexOf(n) >= 0) continue;
          if (!n.querySelector('input[type=radio],input[type=checkbox],textarea,input[type=text],[contenteditable=true]')) continue;
          seen.push(n);
          out.push(n);
        }
      });
      if (!out.length) {
        // 兜底：按 radio/checkbox 的 name 分组
        var groups = {};
        var inputs = doc.querySelectorAll('input[type=radio],input[type=checkbox]');
        for (var j = 0; j < inputs.length; j++) {
          var k = inputs[j].name || ('x' + j);
          (groups[k] = groups[k] || []).push(inputs[j]);
        }
        Object.keys(groups).forEach(function (k) {
          var anc = groups[k][0];
          for (var d = 0; d < 6 && anc && anc.parentElement; d++) anc = anc.parentElement;
          if (anc && seen.indexOf(anc) < 0) { seen.push(anc); out.push(anc); }
        });
      }
    });
    return out;
  }

  function parseBlock(n, idx) {
    var stem = '';
    for (var i = 0; i < SEL.stem.length; i++) {
      var e = null;
      try { e = n.querySelector(SEL.stem[i]); } catch (err) {}
      if (e && txt(e).length > 1) { stem = txt(e); break; }
    }
    var opts = [];
    var optSel = SEL.opt.join(',');
    var lis = [];
    try { lis = n.querySelectorAll(optSel); } catch (e) {}
    for (var j = 0; j < lis.length; j++) {
      var li = lis[j];
      var t = txt(li);
      if (!t || t.length > 300) continue;
      var m = t.match(/^([A-Za-z])[\.、\s:：]/);
      var k = m ? m[1].toUpperCase() : String.fromCharCode(65 + opts.length);
      opts.push({ k: k, t: t });
    }
    if (!stem) {
      // 没有题干容器：整块文本去掉选项行
      var all = txt(n);
      var cut = all.length;
      opts.forEach(function (o) { var p = all.indexOf(o.t); if (p > 0 && p < cut) cut = p; });
      stem = all.slice(0, cut).replace(/^\s*\d+[\.、]\s*/, '').trim();
    } else {
      stem = stem.replace(/^\s*\d+[\.、]\s*/, '');
    }
    var type = 'blank';
    if (n.querySelector('input[type=checkbox]')) type = 'multi';
    else if (n.querySelector('input[type=radio]')) type = 'single';

    return { idx: idx, h: hash(stem), stem: stem, opts: opts, type: type, node: n };
  }

  function collect(force) {
    var nodes = findBlocks();
    var list = [];
    for (var i = 0; i < nodes.length; i++) {
      var q = parseBlock(nodes[i], i);
      if (!q.stem || q.stem.length < 3) continue;
      if (!force && SENT[q.h]) continue;
      SENT[q.h] = 1;
      list.push(q);
    }
    Q = nodes.map(function (n, i) { return parseBlock(n, i); });
    if (list.length) {
      post('q', list.map(function (q) {
        return { idx: q.idx, h: q.h, stem: q.stem, opts: q.opts, type: q.type };
      }));
      post('log', 'report ' + list.length + '/' + nodes.length);
    }
    return list.length;
  }

  // ---------- 回填 ----------
  function fire(el, type) {
    try { el.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, view: window })); } catch (e) {}
  }

  function clickOption(node, letter) {
    var lis = [];
    try { lis = node.querySelectorAll('ul.Zy_ulTop > li, li.option, label.option, .answerList li, .optionLi, li'); } catch (e) {}
    for (var i = 0; i < lis.length; i++) {
      var li = lis[i];
      var t = txt(li);
      if (!t || t.length > 300) continue;
      var m = t.match(/^([A-Za-z])[\.、\s:：]/);
      var k = m ? m[1].toUpperCase() : String.fromCharCode(65 + i);
      if (k !== letter) continue;
      var inp = li.querySelector('input[type=radio],input[type=checkbox]');
      if (inp) {
        if (!inp.checked) { try { inp.click(); } catch (e) {} }
        if (!inp.checked) { fire(inp, 'click'); }
      } else {
        try { li.click(); } catch (e) {}
      }
      fire(li, 'mousedown'); fire(li, 'mouseup'); fire(li, 'click');
      return true;
    }
    return false;
  }

  function setValue(el, val) {
    try {
      var proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      var desc = Object.getOwnPropertyDescriptor(proto, 'value');
      if (desc && desc.set) desc.set.call(el, val); else el.value = val;
    } catch (e) { el.value = val; }
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    el.dispatchEvent(new Event('blur', { bubbles: true }));
  }

  window.__cxFill = function (idx, letters, texts, h) {
    var q = null;
    for (var i = 0; i < Q.length; i++) if (Q[i].h === h) { q = Q[i]; break; }
    if (!q) q = Q[idx];
    if (!q || !q.node) { post('log', 'fill miss ' + idx); return; }
    var node = q.node;

    if (letters && letters.length) {
      for (var j = 0; j < letters.length; j++) clickOption(node, String(letters[j]).toUpperCase());
    }
    if (texts && texts.length) {
      var inputs = node.querySelectorAll('textarea,input[type=text],[contenteditable=true]');
      for (var k = 0; k < inputs.length; k++) {
        var v = texts[k] != null ? texts[k] : texts[0];
        if (v == null) continue;
        var el = inputs[k];
        if (el.getAttribute('contenteditable') === 'true') {
          el.innerHTML = '<p>' + esc(v) + '</p>';
          el.dispatchEvent(new Event('input', { bubbles: true }));
        } else {
          setValue(el, v);
        }
      }
      var frames = node.querySelectorAll('iframe');
      for (var f = 0; f < frames.length; f++) {
        try {
          var body = frames[f].contentDocument.body;
          if (body) {
            body.innerHTML = '<p>' + esc(texts[0] || '') + '</p>';
            body.dispatchEvent(new Event('input', { bubbles: true }));
          }
        } catch (e) {}
      }
    }
    post('filled', idx);
  };

  window.__cxGrab = function (force) {
    SENT = {};
    return collect(!!force);
  };

  // ---------- 启动 ----------
  var failCount = 0, domSent = false;
  function tick() {
    if (location.href !== lastURL) {
      lastURL = location.href;
      SENT = {};
      Q = [];
      failCount = 0;
      domSent = false;
    }
    if (!isExamPage()) return;
    var n = collect(false);
    if (n === 0) {
      failCount++;
      // 连续三次抓不到题：把 DOM 存回沙盒，用于校准选择器
      if (failCount === 3 && !domSent) {
        domSent = true;
        try { post('dom', (document.documentElement.outerHTML || '').slice(0, 400000)); } catch (e) {}
      }
    } else {
      failCount = 0;
    }
  }

  var timer = null;
  function schedule() {
    if (timer) return;
    timer = setTimeout(function () { timer = null; tick(); }, 700);
  }

  try {
    new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
  } catch (e) {}
  setInterval(tick, 2500);
  setTimeout(function () { post('exam', isExamPage()); tick(); }, 1200);

  // SPA 路由
  (function () {
    var push = history.pushState, repl = history.replaceState;
    history.pushState = function () { var r = push.apply(this, arguments); setTimeout(tick, 300); return r; };
    history.replaceState = function () { var r = repl.apply(this, arguments); setTimeout(tick, 300); return r; };
    window.addEventListener('popstate', function () { setTimeout(tick, 300); });
  })();

  post('log', 'core ready ' + location.href);
})();
