const collator = new Intl.Collator('pt', { sensitivity: 'base' });

for (const table of document.querySelectorAll('[data-sortable-freguesias]')) {
  const body = table.tBodies[0];
  const buttons = [...table.querySelectorAll('thead button[data-sort-key]')];
  const status = document.getElementById(table.dataset.sortStatus);
  let key = 'estimate';
  let direction = 'descending';

  function updateHeaders() {
    for (const button of buttons) {
      const active = button.dataset.sortKey === key;
      const header = button.closest('th');
      if (active) header.setAttribute('aria-sort', direction);
      else header.removeAttribute('aria-sort');
      button.querySelector('[data-sort-indicator]').textContent = active
        ? (direction === 'ascending' ? '↑' : '↓') : '↕';
      const next = active ? (direction === 'ascending' ? 'descending' : 'ascending')
        : button.dataset.initialDirection;
      button.setAttribute('aria-label', `Ordenar por ${button.dataset.sortLabel}, por ordem ${next === 'ascending' ? 'crescente' : 'decrescente'}`);
    }
  }

  for (const button of buttons) {
    button.disabled = false;
    button.addEventListener('click', () => {
      if (key === button.dataset.sortKey) {
        direction = direction === 'ascending' ? 'descending' : 'ascending';
      } else {
        key = button.dataset.sortKey;
        direction = button.dataset.initialDirection;
      }
      const sign = direction === 'ascending' ? 1 : -1;
      const rows = [...body.rows];
      rows.sort((a, b) => {
        const comparison = key === 'name'
          ? collator.compare(a.dataset.name, b.dataset.name)
          : Number(a.dataset[key]) - Number(b.dataset[key]);
        return comparison ? comparison * sign : collator.compare(a.dataset.name, b.dataset.name);
      });
      body.append(...rows);
      updateHeaders();
      status.textContent = `Ordenado por ${button.dataset.sortLabel}, por ordem ${direction === 'ascending' ? 'crescente' : 'decrescente'}.`;
    });
  }
  updateHeaders();
}
