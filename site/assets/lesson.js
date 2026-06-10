/* ============================================================
   BRAINZIE — INTERACTIVE LESSON STEPPER (shared)
   Drives every lesson page. Features:
     • one step at a time, with Previous/Next ABOVE and BELOW the step
     • clickable progress dots
     • full-screen mode (only the current step shows) via a glowing button
     • each step change is a browser history entry, so Back/Forward move steps
     • code "Copy" buttons
   Page mechanics only — never part of the lesson content shown to students.

   Markup contract (see tools/templates/lesson.html):
     .lesson-progress  > #cur, #total, #dots, .fs-title, .fs-btn
     #steps            > .step (first may be .active)
     .lesson-nav       > .prev, .next   (this bottom nav is cloned to the top)
   ============================================================ */
(function () {
  const steps = Array.from(document.querySelectorAll('.step'));
  if (!steps.length) return;
  const total = steps.length;

  const stepsEl = document.getElementById('steps');
  const curEl = document.getElementById('cur');
  const totalEl = document.getElementById('total');
  const dotsEl = document.getElementById('dots');
  if (totalEl) totalEl.textContent = total;

  // --- Previous/Next, both above and below the step ---------------------
  const bottomNav = document.querySelector('.lesson-nav');
  let topNav = null;
  if (bottomNav) {
    topNav = bottomNav.cloneNode(true);
    topNav.classList.add('top');
    stepsEl.parentNode.insertBefore(topNav, stepsEl);
  }
  const prevBtns = Array.from(document.querySelectorAll('.lesson-nav .prev'));
  const nextBtns = Array.from(document.querySelectorAll('.lesson-nav .next'));

  // --- Progress dots ----------------------------------------------------
  let dots = [];
  if (dotsEl) {
    steps.forEach((_, n) => {
      const d = document.createElement('button');
      d.className = 'dot';
      d.type = 'button';
      d.title = 'Step ' + (n + 1);
      d.addEventListener('click', () => go(n));
      dotsEl.appendChild(d);
    });
    dots = Array.from(dotsEl.children);
  }

  let i = 0;

  function render(n) {
    i = Math.max(0, Math.min(total - 1, n));
    steps.forEach((s, k) => s.classList.toggle('active', k === i));
    dots.forEach((d, k) => {
      d.classList.toggle('current', k === i);
      d.classList.toggle('done', k < i);
    });
    if (curEl) curEl.textContent = i + 1;
    prevBtns.forEach(b => (b.disabled = i === 0));
    nextBtns.forEach(b => (b.textContent = i === total - 1 ? 'Finish ✓' : 'Next →'));
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  // --- Navigation that records browser history --------------------------
  function go(n, replace) {
    const target = Math.max(0, Math.min(total - 1, n));
    const state = { brzStep: target };
    const hash = '#step-' + (target + 1);
    try {
      if (replace) history.replaceState(state, '', hash);
      else history.pushState(state, '', hash);
    } catch (e) { /* file:// etc. — navigation still works, just no history */ }
    render(target);
  }

  function stepFromHash() {
    const m = /^#step-(\d+)$/.exec(location.hash);
    return m ? Math.max(0, Math.min(total - 1, parseInt(m[1], 10) - 1)) : 0;
  }

  prevBtns.forEach(b => b.addEventListener('click', () => go(i - 1)));
  nextBtns.forEach(b => b.addEventListener('click', () => { if (i < total - 1) go(i + 1); }));

  // Back/Forward: render the step from the popped state without pushing again.
  window.addEventListener('popstate', e => {
    const n = (e.state && typeof e.state.brzStep === 'number') ? e.state.brzStep : stepFromHash();
    render(n);
  });

  document.addEventListener('keydown', e => {
    const tag = (e.target.tagName || '').toLowerCase();
    if (tag === 'input' || tag === 'textarea') return;
    if (e.key === 'ArrowRight') go(i + 1);
    if (e.key === 'ArrowLeft') go(i - 1);
  });

  // --- Full-screen mode -------------------------------------------------
  const fsBtn = document.querySelector('.fs-btn');
  const fsTitle = document.querySelector('.lesson-progress .fs-title');
  if (fsTitle) {
    const h1 = document.querySelector('.pagehead h1');
    fsTitle.textContent = h1 ? h1.textContent : (document.title.split('—')[0] || '').trim();
  }
  const FS_SEEN = 'brz-fs-seen';
  if (fsBtn) {
    let seen = false;
    try { seen = localStorage.getItem(FS_SEEN) === '1'; } catch (e) {}
    if (!seen) fsBtn.classList.add('glow');

    function setFs(on) {
      document.body.classList.toggle('lesson-fullscreen', on);
      fsBtn.textContent = on ? '✕' : '⛶';
      fsBtn.title = on ? 'Exit full screen' : 'Full screen — show only this step';
      fsBtn.setAttribute('aria-label', fsBtn.title);
    }
    fsBtn.title = 'Full screen — show only this step';
    fsBtn.setAttribute('aria-label', fsBtn.title);
    fsBtn.addEventListener('click', () => {
      fsBtn.classList.remove('glow');
      try { localStorage.setItem(FS_SEEN, '1'); } catch (e) {}
      setFs(!document.body.classList.contains('lesson-fullscreen'));
    });
    document.addEventListener('keydown', e => {
      if (e.key === 'Escape' && document.body.classList.contains('lesson-fullscreen')) setFs(false);
    });
  }

  // --- Code "Copy" buttons ---------------------------------------------
  document.querySelectorAll('.copy').forEach(btn => {
    btn.addEventListener('click', () => {
      const code = btn.closest('.code').querySelector('code').innerText;
      navigator.clipboard.writeText(code).then(() => {
        btn.textContent = 'Copied!';
        btn.classList.add('copied');
        setTimeout(() => { btn.textContent = 'Copy'; btn.classList.remove('copied'); }, 1600);
      });
    });
  });

  // --- Start on the step named in the URL (deep-link / refresh friendly) -
  go(stepFromHash(), true);
})();
