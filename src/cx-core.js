/* CXExamAI 页面端核心 v1.1
 * 抓题不依赖 input：兼容学习通考试页的"卡片式选项"（div 点击）
 */
(function () {
  if (window.__cxCore) return;
  window.__cxCore = 1;

  var H = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.cxNative;
  var SENT = {}, Q = [], lastURL = location.href, failCount = 0, domSent = false;

  function post(t, d) { try { H && H.postMessage({ t: t, d: d, u: location.href }); } catch (e) {} }
  function txt(el) { return el ? ((el.innerText || el.textContent || '').replace(/\u00a0/g, ' ').replace(/\s+/g, ' ').trim()) : ''; }
  function hash(s) { var h = 5381; for (var i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0; return (h >>> 0).toString(36); }
  function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }

  // ---------- 页面判定 ----------
  function isExamPage() {
    var u = location.href;
    if (/reVersionTestStartNew|exam-ans\/exam\/test|\/exam\/test\//i.test(u)) return true;
    try {
      if (document.querySelector('.answerMain, .questionWrap, .answerList')) return true;
    } catch (e) {}
    var t = '';
    try { t = (document.body ? document.body.innerText : '').slice(0, 3000); } catch (e) {}
    if (/答题卡/.test(t) && /（共\s*\d+\s*题/.test(t)) return true;
    return false;
  }
  function isFacePage() { return /face|verify|liveness|renzheng|certif/i.test(location.href); }

  // ---------- 防切屏（仅考试页、非人脸页） ----------
  try {
    if (isExamPage() && !isFacePage()) {
      try {
        Object.defineProperty(document, 'hidden', { get: function () { return false; }, configurable: false });
        Object.defineProperty(document, 'visibilityState', { get: function () { return 'visible'; }, configurable: false });
      } catch (e) {}
      try {
        var AEL = EventTarget.prototype.addEventListener;
        EventTarget.prototype.addEventListener = function (type, fn, opt) {
          if ((this === document || this === window) && /^(visibilitychange|pagehide)$/i.test(type)) return;
          return AEL.call(this, type, fn, opt);
        };
      } catch (e) {}
      try {
        Object.defineProperty(window, 'onblur', { get: function () { return null; }, set: function () {}, configurable: false });
        Object.defineProperty(window, 'onfocus', { get: function () { return null; }, set: function () {}, configurable: false });
        document.hasFocus = function () { return true; };
      } catch (e) {}
      post('log', 'guard on ' + location.href);
    }
  } catch (e) {}

  // ---------- 文档集合 ----------
  function docs(root, depth) {
    var out = [root];
    if (depth <= 0) return out;
    var frames = [];
    try { frames = root.querySelectorAll('iframe'); } catch (e) {}
    for (var i = 0; i < frames.length; i++) {
      try { var d = frames[i].contentDocument; if (d) out = out.concat(docs(d, depth - 1)); } catch (e) {}
    }
    return out;
  }

  // ---------- 选项识别（不依赖 input） ----------
  function optLetter(t) {
    if (!t || t.length > 240) return '';
    var m = t.match(/^([A-H])\s*[\.、,，:：\)）]\s*/);
    if (!m) m = t.match(/^([A-H])[\s\u3000]+(?=\S)/);
    return m ? m[1] : '';
  }
  function isOpt(t) { return !!optLetter(t); }

  function optionNodes(doc) {
    var res = [], all;
    try { all = doc.querySelectorAll('li,div,label,p,span,a'); } catch (e) { return res; }
    for (var i = 0; i < all.length && i < 6000; i++) {
      var el = all[i], t = txt(el);
      if (!isOpt(t)) continue;
      if (t.length > 160) continue;
      var p = el.parentElement;
      if (p) {
        var pt = txt(p);
        if (pt === t) continue;                       // 与父同文本，取更外层
        if (optLetter(pt) === optLetter(t)) continue; // 父也是同字母选项 → 自己是内层
      }
      res.push(el);
    }
    return res;
  }

  function groupOptions(doc) {
    var nodes = optionNodes(doc), groups = [], cur = null;
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i], L = optLetter(txt(el));
      if (!L) continue;
      if (!cur || L === 'A' || L.charCodeAt(0) <= cur.last.charCodeAt(0)) {
        cur = { items: [el], last: L };
        groups.push(cur);
      } else {
        cur.items.push(el);
        cur.last = L;
      }
    }
    return groups.filter(function (g) { return g.items.length >= 2; });
  }

  function commonAncestor(els) {
    var a = els[0];
    while (a) {
      var ok = true;
      for (var i = 1; i < els.length; i++) { if (!a.contains(els[i])) { ok = false; break; } }
      if (ok) return a;
      a = a.parentElement;
    }
    return null;
  }

  function stemOf(block, opts) {
    var all = txt(block), cut = all.length;
    for (var i = 0; i < opts.length; i++) {
      var p = all.indexOf(opts[i].text);
      if (p > 0 && p < cut) cut = p;
    }
    var s = all.slice(0, cut);
    s = s.replace(/^\s*\d+\s*[\.、]\s*/, '')
         .replace(/^\s*[（(]\s*[\d.]+\s*分\s*[)）]\s*/, '')
         .replace(/\s+/g, ' ')
         .trim();
    return s;
  }

  function typeOf(block, stem) {
    var head = (stem || '') + ' ' + txt(block).slice(0, 120);
    if (/多选题|多项选择|不定项/.test(head)) return 'multi';
    if (/判断题|判断/.test(head)) return 'single';
    if (/填空题|简答题|论述题|名词解释/.test(head)) return 'blank';
    return 'single';
  }

  function collectFromDoc(doc, offset) {
    var groups = groupOptions(doc), out = [];
    for (var i = 0; i < groups.length; i++) {
      var g = groups[i];
      var anc = commonAncestor(g.items);
      if (!anc) continue;
      var block = anc.parentElement || anc;
      var opts = [];
      for (var j = 0; j < g.items.length; j++) {
        opts.push({ k: optLetter(txt(g.items[j])), t: txt(g.items[j]), el: g.items[j] });
      }
      var stem = stemOf(block, opts);
      if (!stem || stem.length < 3) stem = stemOf(anc, opts);
      if (!stem || stem.length < 3) continue;
      out.push({
        idx: offset + out.length,
        h: hash(stem),
        stem: stem,
        opts: opts.map(function (o) { return { k: o.k, t: o.t }; }),
        type: typeOf(block, stem),
        node: block,
        items: g.items
      });
    }
    return out;
  }

  // ---------- 学习通考试页（exam-ans v3）专用：结构稳定 ----------
  function collectChaoxing() {
    var out = [];
    var blocks = [];
    try { blocks = document.querySelectorAll('.answerMain'); } catch (e) {}
    if (!blocks.length) {
      try { blocks = document.querySelectorAll('.answerCon'); } catch (e) {}
    }
    for (var i = 0; i < blocks.length; i++) {
      var n = blocks[i];
      var items = [];
      try { items = n.querySelectorAll('.answerList'); } catch (e) {}
      var opts = [];
      for (var j = 0; j < items.length; j++) {
        var it = items[j];
        var L = (it.getAttribute('name') || '').toUpperCase();
        if (!/^[A-H]$/.test(L)) {
          var no = it.querySelector('.No');
          if (no) L = txt(no).toUpperCase();
        }
        if (!/^[A-H]$/.test(L)) continue;
        var info = it.querySelector('.answerInfo') || it;
        var t = txt(info);
        if (!t || t.length > 400) continue;
        opts.push({ k: L, t: t, el: it });
      }
      var tnEl = n.querySelector('input[name^="typeName"]');
      var tnVal = tnEl ? (tnEl.value || '') : '';
      var textType = /简答|论述|名词解释|填空|分析|计算|材料/.test(tnVal);
      if (opts.length < 2 && !textType) continue;

      opts.sort(function (a, b) { return a.k < b.k ? -1 : (a.k > b.k ? 1 : 0); });

      var stem = '';
      var tit = n.querySelector('.tit');
      if (tit) {
        var ps = tit.querySelectorAll('p');
        var parts = [];
        for (var k = 0; k < ps.length; k++) {
          var sp = txt(ps[k]);
          if (sp) parts.push(sp);
        }
        if (parts.length) {
          stem = parts.join(' ');
        } else {
          var clone = tit.cloneNode(true);
          var h3 = clone.querySelector('h3');
          if (h3) h3.parentNode.removeChild(h3);
          stem = txt(clone);
        }
      }
      stem = stem.replace(/^\s*\d+\s*[\.、．]\s*/, '')
                 .replace(/^[（(]\s*[\d.]+\s*分\s*[)）]\s*/, '')
                 .replace(/\s+/g, ' ')
                 .trim();
      if (!stem || stem.length < 2) continue;

      var type = 'single';
      if (/多选|不定项/.test(tnVal)) type = 'multi';
      else if (/判断/.test(tnVal)) type = 'single';
      else if (textType) type = 'blank';
      else if (/多选题/.test(txt(tit))) type = 'multi';

      out.push({
        idx: out.length,
        h: hash(stem),
        stem: stem,
        opts: opts.map(function (o) { return { k: o.k, t: o.t }; }),
        type: type,
        node: n,
        items: opts.map(function (o) { return o.el; })
      });
    }
    return out;
  }

  // 已知容器优先（老版学习通 / 作业页）
  function collectFromContainers() {
    var sels = ['.questionLi', '.TiMu', 'div[data-qid]', '.exam-question', '.queBox'];
    var out = [];
    docs(document, 3).forEach(function (doc) {
      sels.forEach(function (sel) {
        var list = [];
        try { list = doc.querySelectorAll(sel); } catch (e) {}
        for (var i = 0; i < list.length; i++) {
          var n = list[i];
          var opts = [];
          var lis = [];
          try { lis = n.querySelectorAll('ul.Zy_ulTop > li, li.option, label.option, .answerList li, .optionLi'); } catch (e) {}
          for (var j = 0; j < lis.length; j++) {
            var t = txt(lis[j]);
            if (!t || t.length > 240) continue;
            opts.push({ k: optLetter(t) || String.fromCharCode(65 + opts.length), t: t, el: lis[j] });
          }
          if (opts.length < 2) continue;
          var stem = '';
          var stemSel = ['.Zy_TItle', '.stem', '.question-title', '.mark_name', 'h3'];
          for (var s = 0; s < stemSel.length; s++) {
            var e = n.querySelector(stemSel[s]);
            if (e && txt(e).length > 2) { stem = txt(e); break; }
          }
          if (!stem) stem = stemOf(n, opts);
          if (!stem || stem.length < 3) continue;
          out.push({
            idx: out.length, h: hash(stem), stem: stem.replace(/^\s*\d+\s*[\.、]\s*/, ''),
            opts: opts.map(function (o) { return { k: o.k, t: o.t }; }),
            type: n.querySelector('input[type=checkbox]') ? 'multi' : 'single',
            node: n, items: opts.map(function (o) { return o.el; })
          });
        }
      });
    });
    return out;
  }

  function collect(force) {
    var found = collectChaoxing();
    if (!found.length) found = collectFromContainers();
    if (!found.length) {
      var off = 0;
      docs(document, 3).forEach(function (doc) {
        var part = collectFromDoc(doc, off);
        off += part.length;
        found = found.concat(part);
      });
    }
    Q = found;
    var list = [];
    for (var i = 0; i < found.length; i++) {
      var q = found[i];
      if (!force && SENT[q.h]) continue;
      SENT[q.h] = 1;
      list.push(q);
    }
    if (list.length) {
      post('q', list.map(function (q) {
        return { idx: q.idx, h: q.h, stem: q.stem, opts: q.opts, type: q.type };
      }));
      post('log', 'report ' + list.length + '/' + found.length);
    } else if (found.length && !window.__cxSentLogged) {
      window.__cxSentLogged = 1;
      post('log', 'found ' + found.length + ' but all sent');
    }
    return list.length;
  }

  // ---------- 回填 ----------
  function resolveTarget(el) {
    var t = el, g = 0;
    while (t && g++ < 4) {
      var cls = '';
      try { cls = String(t.className || ''); } catch (e) {}
      if (/answerList|option|choice|item/i.test(cls)) return t;
      t = t.parentElement;
    }
    return el;
  }

  function scopeOf(el) {
    var s = null;
    try { s = el.closest('.answerMain') || el.closest('.answerCon'); } catch (e) {}
    return s || document;
  }

  function stateOf(el) {
    var cls = '';
    try { cls = String(el.className || ''); } catch (e) {}
    var mark = /(^|\s)(cur|check|checked|active|selected|sel|on)(\s|$)/.test(cls) ? '1' : '0';
    var inp = scopeOf(el).querySelector('input[name^="answers"]');
    return mark + '|' + (inp ? inp.value : '');
  }

  function areaOf(el) {
    var r = el.getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  }

  // 直接调用 jQuery 注册的处理函数（最接近真人点击）
  function jqFire(el, type) {
    var $ = window.jQuery || window.$;
    if (!$ || !$._data) return false;
    var evs = null;
    try { evs = $._data(el, 'events'); } catch (e) { return false; }
    if (!evs || !evs[type] || !evs[type].length) return false;
    try {
      evs[type][0].handler.call(el, {
        type: type, target: el, currentTarget: el, delegateTarget: el, srcElement: el,
        preventDefault: function () {}, stopPropagation: function () {},
        isDefaultPrevented: function () { return false; },
        isPropagationStopped: function () { return false; },
        originalEvent: { target: el, type: type, preventDefault: function () {}, stopPropagation: function () {} }
      });
      return true;
    } catch (e) { post('log', 'jq err ' + e); return false; }
  }

  function fireTouch(el) {
    var p = areaOf(el);
    try { el.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, cancelable: true, clientX: p.x, clientY: p.y })); } catch (e) {}
    try {
      var t = new Touch({ identifier: 1, target: el, clientX: p.x, clientY: p.y, pageX: p.x + scrollX, pageY: p.y + scrollY });
      el.dispatchEvent(new TouchEvent('touchstart', { bubbles: true, cancelable: true, touches: [t], targetTouches: [t], changedTouches: [t] }));
      el.dispatchEvent(new TouchEvent('touchend', { bubbles: true, cancelable: true, touches: [], targetTouches: [], changedTouches: [t] }));
    } catch (e) {}
  }

  function fireMouse(el) {
    var p = areaOf(el);
    var o = { bubbles: true, cancelable: true, view: window, clientX: p.x, clientY: p.y };
    try { el.dispatchEvent(new MouseEvent('mousedown', o)); } catch (e) {}
    try { el.dispatchEvent(new MouseEvent('mouseup', o)); } catch (e) {}
    try { el.dispatchEvent(new MouseEvent('click', o)); } catch (e) {}
  }

  function selectItem(el, done) {
    var target = resolveTarget(el);
    var before = stateOf(target);
    var types = ['click', 'tap', 'touchend', 'touchstart', 'mousedown'];
    for (var i = 0; i < types.length; i++) {
      if (jqFire(target, types[i])) {
        post('log', 'jq ' + types[i]);
        setTimeout(function () {
          var after = stateOf(target);
          post('log', 'state ' + before + ' -> ' + after);
          done && done(after !== before);
        }, 200);
        return;
      }
    }
    fireTouch(target);
    setTimeout(function () {
      if (stateOf(target) !== before) {
        post('log', 'touch ok ' + stateOf(target));
        done && done(true);
        return;
      }
      fireMouse(target);
      setTimeout(function () {
        var after = stateOf(target);
        post('log', 'state ' + before + ' -> ' + after);
        done && done(after !== before);
      }, 240);
    }, 220);
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

  function fillTexts(node, texts) {
    if (!texts || texts[0] == null) return;
    // UEditor：优先后端接口写入，保证提交时同步
    try {
      var html = '<p>' + esc(texts[0]) + '</p>';
      var holder = node.querySelector('.edui-editor');
      var id = holder ? holder.id : '';
      if (id && window.UE && window.UE.getEditor) {
        var ed = window.UE.getEditor(id);
        if (ed && ed.setContent) { ed.setContent(html); post('log', 'ue setContent ' + id); }
      }
    } catch (e) { post('log', 'ue fail ' + e); }
    var inputs = node.querySelectorAll('textarea,input[type=text],[contenteditable=true]');
    for (var i = 0; i < inputs.length; i++) {
      var v = texts[i] != null ? texts[i] : texts[0];
      var el = inputs[i];
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

  window.__cxFill = function (idx, letters, texts, h) {
    var q = null, i;
    for (i = 0; i < Q.length; i++) if (Q[i].h === h) { q = Q[i]; break; }
    if (!q) q = Q[idx];
    if (!q || !q.node) { post('log', 'fill miss ' + idx + ' q=' + Q.length); return; }

    var elems = [];
    if (letters && letters.length) {
      for (i = 0; i < letters.length; i++) {
        var L = String(letters[i]).toUpperCase();
        var it = findItem(q.node, L);
        if (it) elems.push(it);
        else post('log', 'item miss ' + L);
      }
    }
    fillTexts(q.node, texts);

    var n = 0;
    function step() {
      if (n >= elems.length) { post('filled', idx); return; }
      var el = elems[n++];
      selectItem(el, function (ok) {
        post('log', 'sel ' + (ok ? 'ok' : 'fail'));
        setTimeout(step, 120);
      });
    }
    step();
  };

  window.__cxGrab = function (force) {
    SENT = {};
    var n = collect(true);
    post('log', 'manual grab ' + n + ' total=' + Q.length + ' url=' + location.href);
    if (n === 0) {
      try { post('dom', (document.documentElement.outerHTML || '').slice(0, 400000)); } catch (e) {}
      try {
        var t = (document.body ? document.body.innerText : '').slice(0, 600);
        post('log', 'page text: ' + t.replace(/\s+/g, ' '));
      } catch (e) {}
    }
    return n;
  };

  // ---------- 启动 ----------
  function tick() {
    if (location.href !== lastURL) {
      lastURL = location.href;
      SENT = {}; Q = []; failCount = 0; domSent = false;
    }
    if (!isExamPage()) return;
    var n = collect(false);
    if (n === 0) {
      failCount++;
      if (failCount === 4 && !domSent) {
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
    timer = setTimeout(function () { timer = null; tick(); }, 600);
  }

  try {
    new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
  } catch (e) {}
  setInterval(tick, 1800);
  setTimeout(function () { post('exam', isExamPage()); tick(); }, 800);

  (function () {
    var push = history.pushState, repl = history.replaceState;
    history.pushState = function () { var r = push.apply(this, arguments); setTimeout(tick, 300); return r; };
    history.replaceState = function () { var r = repl.apply(this, arguments); setTimeout(tick, 300); return r; };
    window.addEventListener('popstate', function () { setTimeout(tick, 300); });
  })();

  post('log', 'core v1.1 ready ' + location.href);
})();
