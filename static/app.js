document.addEventListener('DOMContentLoaded', () => {
  const form = document.querySelector('[data-dirty-form]');
  if (form) {
    let dirty = false;
    form.addEventListener('input', () => { dirty = true; });
    form.addEventListener('change', () => { dirty = true; });
    form.addEventListener('submit', () => { dirty = false; });
    window.addEventListener('beforeunload', event => {
      if (dirty) { event.preventDefault(); event.returnValue = ''; }
    });
  }
  const group = document.querySelector('#id_group');
  if (group) {
    const update = () => { group.closest('.field').hidden = document.querySelector('input[name="kind"]:checked')?.value !== 'group'; };
    document.querySelectorAll('input[name="kind"]').forEach(input => input.addEventListener('change', update));
    update();
  }
});
