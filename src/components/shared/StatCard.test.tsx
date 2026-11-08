import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { expect, it } from 'vitest';
import { StatCard } from './StatCard';

it.each([[undefined,0], [0,0], [25,25], [150,100], [-1,0], [NaN,0], [Infinity,0]])(
  'renders a safe bar for progress %s', (progress, expected) => {
    const html = renderToStaticMarkup(createElement(StatCard, {label:'Inventory', value:0, progress}));
    expect(html).toContain('width:'+expected+'%');
    expect(html).not.toContain('width:40%');
  });
it('names the actual ratio instead of implying a currency target', () => {
  const html = renderToStaticMarkup(createElement(StatCard, {label:'Inventory value',value:500,progress:50,progressLabel:'Share of stocked items with a recorded cost'}));
  expect(html).toContain('aria-label="Share of stocked items with a recorded cost"');
  expect(html).toContain('aria-valuenow="50"');
});
