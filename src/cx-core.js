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

  // 清洗题干里的动态噪声：单题限时倒计时、剩余时间、分值、题号。
  // 学习通的倒计时每秒变化，若不剥离，stem 每次不同 → hash 变 → 去重失效
  // （同一题被反复识别/请求），回填时 h 也对不上导致 fill miss。
  function cleanStem(s) {
    s = String(s || '');
    s = s.replace(/单题限时\s*\d+\s*[:：]\s*\d+/g, '')
         .replace(/单题限时\s*\d+\s*分?\s*\d*\s*秒?/g, '')
         .replace(/剩余时间\s*\d+\s*[:：]\s*\d+/g, '')
         .replace(/倒计时\s*\d+\s*[:：]?\s*\d*/g, '')
         .replace(/考试限时\s*\d+\s*[:：]\s*\d+/g, '')
         .replace(/限时\s*\d+\s*[:：]\s*\d+/g, '')
         .replace(/第\s*\d+\s*题/g, '')
         .replace(/[（(]\s*\d+(\.\d+)?\s*分\s*[)）]/g, '')
         .replace(/\b\d+(\.\d+)?\s*分\b/g, '')
         .replace(/^\s*\d+\s*[.、．]\s*/, '')
         .replace(/^[\s　]*[（(]\s*\d+\s*[)）][\s　]*/, '')
         .replace(/[\s　]+/g, ' ')
         .trim();
    return s;
  }

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

  // 按选项元素在屏幕上的真实位置（先上后下、同行先左后右）排序，
  // 然后按视觉顺序重新编号 A/B/C/D。学习通把显示顺序和 DOM name 打乱时，
  // 只有视觉顺序才和用户看到的一致；题库/缓存再按文本锚定即可对上。
  function orderByVisual(opts) {
    for (var i = 0; i < opts.length; i++) {
      var el = opts[i].el, y = 1e9, x = 0;
      if (el && el.getBoundingClientRect) {
        try { var r = el.getBoundingClientRect(); y = r.top; x = r.left; } catch (e) {}
      }
      opts[i]._y = y; opts[i]._x = x;
    }
    opts.sort(function (a, b) {
      var dy = a._y - b._y;
      if (Math.abs(dy) > 6) return dy;   // 不同行
      return a._x - b._x;                // 同一行按左右
    });
    for (var j = 0; j < opts.length; j++) opts[j].k = String.fromCharCode(65 + j);
    return opts;
  }

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
    return cleanStem(s);
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

  function collectImages(node) {
    var out = [], seen = {};
    var imgs = [];
    try { imgs = node.querySelectorAll('img'); } catch (e) {}
    for (var i = 0; i < imgs.length && out.length < 3; i++) {
      var src = imgs[i].src || imgs[i].getAttribute('data-src') || '';
      if (!src || /^data:/.test(src) || seen[src]) continue;
      var w = imgs[i].naturalWidth || imgs[i].width || 0;
      var h = imgs[i].naturalHeight || imgs[i].height || 0;
      if (w && h && (w < 50 || h < 30)) continue;   // 忽略图标
      seen[src] = 1;
      out.push(src);
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

      // 学习通会用 CSS/JS 把选项显示位置与 DOM 的 name/字母错位。
      // 按屏幕真实坐标排序并按视觉顺序重编 k，面板显示与点选才一致。
      orderByVisual(opts);

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
      stem = cleanStem(stem);

      // 题干正文有时不在 .tit（如图文混排的简答题），清洗后过短。
      // 退回整块文本再清洗一次，仍不行则用题图片 URL 做稳定身份。
      if (stem.length < 4) {
        var full = cleanStem(txt(n));
        if (full.length > stem.length) stem = full;
      }
      var imgs0 = collectImages(n);
      if (stem.length < 2 && imgs0.length) {
        stem = '【图片题】' + hash(imgs0[0]);  // URL 稳定，倒计时无关
      }
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
        imgs: imgs0,
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

  // 题干 + 按字母排序的选项内容 → 去重指纹。选项乱序视为不同题，
  // 避免同一题干换了一套选项时被 SENT 当成已发过而漏答/串答案。
  function fpOf(q) {
    var parts = (q.opts || []).map(function (o) { return (o.k || '') + '=' + (o.t || ''); });
    parts.sort();
    return q.stem + '|' + parts.join(';');
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
      var fp = hash(fpOf(q));
      q._fp = fp;
      var now = Date.now();
      if (!force && SENT[fp] && now - SENT[fp] < 300000) continue;
      SENT[fp] = now;
      list.push(q);
    }
    if (list.length) {
      post('q', list.map(function (q) {
        return { idx: q.idx, h: q.h, stem: q.stem, opts: q.opts, type: q.type, imgs: q.imgs || [] };
      }));
      post('log', 'report ' + list.length + '/' + found.length);
    } else if (found.length && !window.__cxSentLogged) {
      window.__cxSentLogged = 1;
      post('log', 'found ' + found.length + ' but all sent');
    }
    return found.length;
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

  function touchEvent(el, type, x, y) {
    var ev;
    try { ev = document.createEvent('Event'); } catch (e) { ev = new Event(type, { bubbles: true, cancelable: true }); }
    ev.initEvent(type, true, true);
    var pt = { identifier: 1, target: el, clientX: x, clientY: y, pageX: x + scrollX, pageY: y + scrollY, screenX: x, screenY: y };
    try {
      var list = (type === 'touchend' || type === 'touchcancel') ? [] : [pt];
      Object.defineProperty(ev, 'touches', { value: list, configurable: true });
      Object.defineProperty(ev, 'targetTouches', { value: list, configurable: true });
      Object.defineProperty(ev, 'changedTouches', { value: [pt], configurable: true });
    } catch (e) {}
    try { el.dispatchEvent(ev); } catch (e) {}
  }

  function fireTouch(el) {
    var p = areaOf(el);
    try { el.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, cancelable: true, clientX: p.x, clientY: p.y })); } catch (e) {}
    touchEvent(el, 'touchstart', p.x, p.y);
    setTimeout(function () { touchEvent(el, 'touchend', p.x, p.y); }, 40);
  }

  function fireMouse(el) {
    var p = areaOf(el);
    var o = { bubbles: true, cancelable: true, view: window, clientX: p.x, clientY: p.y };
    try { el.dispatchEvent(new MouseEvent('mousedown', o)); } catch (e) {}
    try { el.dispatchEvent(new MouseEvent('mouseup', o)); } catch (e) {}
    try { el.dispatchEvent(new MouseEvent('click', o)); } catch (e) {}
  }

  function diagOf(el) {
    var $ = window.jQuery || window.$;
    var lib = 'none';
    try {
      if ($ && $.fn && $.fn.jquery) lib = 'jQuery' + $.fn.jquery;
      else if ($ && $.zepto) lib = 'zepto';
      else if ($) lib = 'other';
    } catch (e) {}
    var types = '-';
    try {
      if ($ && $._data) {
        var evs = $._data(el, 'events');
        if (evs) types = Object.keys(evs).join('/');
      }
    } catch (e) {}
    return lib + ' ev=' + types;
  }

  function pointPress(el) {
    var r = el.getBoundingClientRect();
    var x = r.left + r.width / 2, y = r.top + r.height / 2;
    var hit = null;
    try { hit = document.elementFromPoint(x, y); } catch (e) {}
    var target = hit || el;
    try {
      var box = target.closest ? target.closest('.answerList') : null;
      if (box) target = box;
    } catch (e) {}
    post('log', 'point ' + (target.className || target.tagName));
    fireTouch(target);
    setTimeout(function () { fireMouse(target); }, 120);
  }

  function jqTrigger(el, type) {
    var $ = window.jQuery || window.$;
    if (!$ || !$.fn || typeof $.fn.trigger !== 'function') return false;
    try { $(el).trigger(type); return true; } catch (e) { return false; }
  }

  function selectItem(el, done) {
    var target = resolveTarget(el);
    var before = stateOf(target);
    post('log', 'click ' + (target.className || '') + ' | ' + diagOf(target));

    // 0) jQuery/zepto trigger，走完整委托链
    var trig = ['click', 'tap', 'touchend'];
    for (var t = 0; t < trig.length; t++) {
      if (jqTrigger(target, trig[t])) {
        if (stateOf(target) !== before) {
          post('log', 'trigger ' + trig[t] + ' ok ' + stateOf(target));
          done && done(true);
          return;
        }
      }
    }

    // 1) jQuery/zepto 里注册的处理函数，直接调用
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

    // 2) 触摸（Safari 兼容写法）
    fireTouch(target);
    setTimeout(function () {
      if (stateOf(target) !== before) {
        post('log', 'touch ok ' + stateOf(target));
        done && done(true);
        return;
      }
      // 3) 鼠标
      fireMouse(target);
      setTimeout(function () {
        if (stateOf(target) !== before) {
          post('log', 'mouse ok ' + stateOf(target));
          done && done(true);
          return;
        }
        // 4) 坐标命中 + 内部元素兜底
        pointPress(target);
        setTimeout(function () {
          if (stateOf(target) !== before) {
            post('log', 'point ok ' + stateOf(target));
            done && done(true);
            return;
          }
          try { var info = target.querySelector('.answerInfo') || target.querySelector('cc'); if (info) fireMouse(info); } catch (e) {}
          setTimeout(function () {
            var after = stateOf(target);
            post('log', 'state ' + before + ' -> ' + after + ' (all failed)');
            done && done(after !== before);
          }, 200);
        }, 320);
      }, 240);
    }, 220);
  }

  // 点击全部失败时的兜底：直接写 answers 隐藏域并加选中样式
  function forceSelect(el, letter, type) {
    try {
      var box = null;
      try { box = el.closest ? el.closest('.answerMain') : null; } catch (e) {}
      var tv = '';
      if (box) {
        var tn = box.querySelector('input[name^="typeName"]');
        tv = tn ? (tn.value || '') : '';
      }
      var multi = /多选|不定项/.test(tv) || type === 'multi';
      var qid = box ? (box.getAttribute('data') || '') : '';
      var inp = null;
      if (qid) inp = document.querySelector('input[name="answers' + qid + '"]');
      if (!inp && box) inp = box.querySelector('input[name^="answers"]');
      if (!inp) inp = document.querySelector('input[name^="answers"]');
      if (!inp) { post('log', 'force no input'); return false; }
      var cur = inp.value || '';
      var parts = cur ? cur.split(/[,\s|#]+/).filter(Boolean) : [];
      if (multi) {
        if (parts.indexOf(letter) < 0) parts.push(letter);
        parts.sort();
      } else {
        parts = [letter];
      }
      inp.value = parts.join(',');
      try { inp.dispatchEvent(new Event('input', { bubbles: true })); } catch (e) {}
      try { inp.dispatchEvent(new Event('change', { bubbles: true })); } catch (e) {}
      try { el.classList.add('cur'); } catch (e) {}
      try { var no = el.querySelector('.No'); if (no) no.style.color = '#fff'; } catch (e) {}
      post('log', 'force ' + letter + ' answers=' + inp.value);
      return true;
    } catch (e) { post('log', 'force err ' + e); return false; }
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
    if (!texts || texts[0] == null || String(texts[0]).length === 0) return;
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

  // 只按内容 hash 精确定位。绝不按 idx 回退：作答有 1.5s 起 + 每题 2s 的延迟，
  // 延迟期间用户可能已翻页，Q 被 tick() 重建，此时 idx 会指向新页另一道题。
  function findQ(idx, h) {
    for (var i = 0; i < Q.length; i++) if (Q[i].h === h) return Q[i];
    return null;
  }

  // 题目节点是否仍挂在文档树上。翻页/切题后旧节点被移除，必须放弃回填，
  // 否则 evaluateJavaScript 可能命中复用 DOM 的别处元素。
  function nodeLive(node) {
    if (!node) return false;
    try {
      if (typeof node.isConnected === 'boolean') return node.isConnected;
      var d = node.ownerDocument;
      return !!(d && d.documentElement && d.documentElement.contains(node));
    } catch (e) { return false; }
  }

  window.__cxFill = function (idx, letters, texts, h) {
    post('log', 'fill enter idx=' + idx + ' letters=' + JSON.stringify(letters) + ' h=' + h + ' Q=' + Q.length);
    try {
      doFill(idx, letters, texts, h);
    } catch (e) {
      post('log', 'fill error ' + (e && e.message ? e.message : e));
      try {
        var q2 = findQ(idx, h);
        if (q2 && nodeLive(q2.node)) { fillTexts(q2.node, texts); post('filled', idx); }
      } catch (e2) {}
    }
  };

  // 在题目节点里按字母定位选项 DOM。学习通 .answerList 用 name="A" 标记；
  // 老版卡片用 .No 文本或选项首字母。这个函数曾在某些版本被误删，导致
  // doFill 抛 ReferenceError 被吞掉、自动填答静默失效。
  function findItem(block, letter) {
    if (!block || !letter) return null;
    letter = String(letter).toUpperCase();
    var named = [];
    try { named = block.querySelectorAll('[name]'); } catch (e) {}
    for (var n = 0; n < named.length; n++) {
      if ((named[n].getAttribute('name') || '').toUpperCase() === letter) return named[n];
    }
    // 卡片式：.answerList 里的 .No 文本就是字母
    var nos = [];
    try { nos = block.querySelectorAll('.answerList .No, .answerList .no'); } catch (e) {}
    for (var m = 0; m < nos.length; m++) {
      if (txt(nos[m]).toUpperCase() === letter) {
        return nos[m].closest ? (nos[m].closest('.answerList') || nos[m]) : nos[m].parentElement;
      }
    }
    // 兜底：选项文本以 "A." / "A、" 开头的元素
    var cands = [];
    try { cands = block.querySelectorAll('li,div,label,span,a,p'); } catch (e) {}
    for (var i = 0; i < cands.length; i++) {
      var el = cands[i], t = txt(el);
      if (!t || t.length > 240) continue;
      if (optLetter(t) !== letter) continue;
      var p = el.parentElement;
      if (p && optLetter(txt(p)) === letter) continue;
      return el;
    }
    return null;
  }

  function doFill(idx, letters, texts, h) {
    var q = findQ(idx, h), i;
    if (!q || !q.node) { post('log', 'fill miss ' + idx + ' h=' + h + ' q=' + Q.length); return; }
    if (!nodeLive(q.node)) { post('log', 'fill skip: node detached ' + h); return; }

    var elems = [];
    if (letters && letters.length) {
      for (i = 0; i < letters.length; i++) {
        var L = String(letters[i]).toUpperCase();
        // q.items 与 q.opts 顺序一致，且抓题时已按屏幕视觉顺序排序/编号。
        // 直接用字母对应的索引取元素，避免 name 属性与视觉错位时点错。
        var vi = L.charCodeAt(0) - 65;
        var it = (q.items && vi >= 0 && vi < q.items.length && nodeLive(q.items[vi]))
                 ? q.items[vi] : findItem(q.node, L);
        if (it) elems.push({ el: it, letter: L });
        else post('log', 'item miss ' + L);
      }
    }
    fillTexts(q.node, texts);

    var n = 0;
    function step() {
      if (n >= elems.length) { post('filled', idx); return; }
      var item = elems[n++];
      selectItem(item.el, function (ok) {
        post('log', 'sel ' + item.letter + ' ' + (ok ? 'ok' : 'fail'));
        setTimeout(step, 120);
      });
    }
    step();
  }

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
