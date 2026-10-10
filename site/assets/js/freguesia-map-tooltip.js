const number = new Intl.NumberFormat('pt-PT');

for (const [index, map] of [...document.querySelectorAll('[data-parish-map]')].entries()) {
  const tooltip = map.querySelector('[data-map-tooltip]');
  const name = tooltip.querySelector('[data-tooltip-name]');
  const count = tooltip.querySelector('[data-tooltip-count]');
  tooltip.id = `parish-map-tooltip-${index}`;
  let active = null;

  function position(x, y) {
    const bounds = tooltip.getBoundingClientRect();
    const left = Math.max(12, Math.min(x + 16, window.innerWidth - bounds.width - 12));
    const top = y + bounds.height + 28 > window.innerHeight
      ? Math.max(12, y - bounds.height - 16) : y + 16;
    tooltip.style.left = `${left}px`;
    tooltip.style.top = `${top}px`;
  }

  function show(link, x, y) {
    if (active !== link) active?.removeAttribute('aria-describedby');
    active = link;
    name.textContent = link.dataset.parishName;
    count.textContent = number.format(Number(link.dataset.parishEstimate));
    tooltip.hidden = false;
    link.setAttribute('aria-describedby', tooltip.id);
    position(x, y);
  }

  function hide() {
    tooltip.hidden = true;
    active?.removeAttribute('aria-describedby');
    active = null;
  }

  for (const link of map.querySelectorAll('[data-parish-name]')) {
    // Keep the browser tooltip as a fallback when JavaScript is unavailable.
    link.querySelector('title')?.remove();
    link.addEventListener('pointerenter', event => {
      if (event.pointerType !== 'touch') show(link, event.clientX, event.clientY);
    });
    link.addEventListener('pointermove', event => {
      if (active === link) position(event.clientX, event.clientY);
    });
    link.addEventListener('pointerleave', hide);
    link.addEventListener('focus', () => {
      const bounds = link.getBoundingClientRect();
      show(link, bounds.left + bounds.width / 2, bounds.top + bounds.height / 2);
    });
    link.addEventListener('blur', hide);
    link.addEventListener('click', hide);
    link.addEventListener('keydown', event => {
      if (event.key === 'Escape') hide();
    });
  }
  window.addEventListener('scroll', hide, { passive: true });
  window.addEventListener('resize', hide);
}
