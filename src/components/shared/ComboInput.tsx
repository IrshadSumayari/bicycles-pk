import { useEffect, useId, useRef, useState } from 'react';
import { ChevronDown, Plus } from 'lucide-react';
import { cn } from '@/lib/utils';

export type ComboOption = string | { value: string; hint?: string };

interface ComboInputProps {
  value: string | undefined;
  onChange: (value: string) => void;
  options: ComboOption[];
  name?: string;
  placeholder?: string;
  className?: string;
  disabled?: boolean;
  required?: boolean;
  maxLength?: number;
  /** Comma-separated list (e.g. colours): picking adds to the list. */
  multiple?: boolean;
  /** Shown as `Add "<text>" as a new <newLabel>` when typed text matches no option. */
  newLabel?: string;
  'aria-label'?: string;
}

const splitList = (text: string) => text.split(',').map(part => part.trim());

// A text field with a themed suggestion list. Unlike <datalist>, opening it
// always shows every option (not only those matching the current text), so a
// chosen value can be changed without clearing it first. Typing filters the
// list, and any new value can still be typed.
export function ComboInput({ value = '', onChange, options, name, placeholder, className, disabled, required, maxLength, multiple, newLabel, ...aria }: ComboInputProps) {
  const [open, setOpen] = useState(false);
  const [typed, setTyped] = useState(false);
  const [active, setActive] = useState(-1);
  const wrapper = useRef<HTMLDivElement>(null);
  const list = useRef<HTMLUListElement>(null);
  const listId = useId();

  const all = options.map(o => (typeof o === 'string' ? { value: o } : o));
  const parts = multiple ? splitList(value) : [value.trim()];
  const current = (parts[parts.length - 1] ?? '').toLowerCase();
  const chosen = new Set(parts.slice(0, multiple ? -1 : undefined).map(p => p.toLowerCase()).filter(Boolean));
  const available = multiple ? all.filter(o => !chosen.has(o.value.toLowerCase())) : all;
  const filtered = typed && current ? available.filter(o => o.value.toLowerCase().includes(current) || o.hint?.toLowerCase().includes(current)) : available;
  const exact = all.some(o => o.value.toLowerCase() === current);
  const typedText = (multiple ? parts[parts.length - 1] : value).trim();
  const rows = [...filtered, ...(newLabel && typed && typedText && !exact ? [{ value: typedText, isNew: true }] : [])] as { value: string; hint?: string; isNew?: boolean }[];

  useEffect(() => {
    if (!open) return;
    const close = (event: MouseEvent) => { if (!wrapper.current?.contains(event.target as Node)) setOpen(false); };
    document.addEventListener('mousedown', close);
    return () => document.removeEventListener('mousedown', close);
  }, [open]);

  useEffect(() => {
    if (open && active >= 0) list.current?.children[active]?.scrollIntoView({ block: 'nearest' });
  }, [open, active]);

  const show = () => {
    if (disabled) return;
    setTyped(false);
    setActive(multiple ? -1 : all.findIndex(o => o.value.toLowerCase() === current));
    setOpen(true);
  };
  const pick = (next: string) => {
    if (multiple) {
      const kept = parts.slice(0, -1).filter(Boolean);
      onChange([...kept, next].join(', ') + ', ');
      setTyped(false);
      setActive(-1);
      return; // stay open so several can be picked
    }
    onChange(next);
    setOpen(false);
    setTyped(false);
  };

  const onKeyDown = (event: React.KeyboardEvent<HTMLInputElement>) => {
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      if (!open) return show();
      const step = event.key === 'ArrowDown' ? 1 : -1;
      setActive(index => (rows.length ? (index + step + rows.length) % rows.length : -1));
    } else if (event.key === 'Enter' && open && rows[active]) {
      event.preventDefault();
      pick(rows[active].value);
    } else if ((event.key === 'Escape' || event.key === 'Tab') && open) {
      if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); }
      setOpen(false);
    }
  };

  return (
    <div ref={wrapper} className="relative">
      <input
        name={name}
        value={value}
        placeholder={placeholder}
        disabled={disabled}
        required={required}
        maxLength={maxLength}
        autoComplete="off"
        role="combobox"
        aria-expanded={open}
        aria-controls={listId}
        aria-autocomplete="list"
        aria-activedescendant={open && active >= 0 ? `${listId}-${active}` : undefined}
        className={cn(className, 'pr-10')}
        onChange={event => { onChange(event.target.value); setTyped(true); setActive(-1); setOpen(true); }}
        onClick={() => !open && show()}
        onKeyDown={onKeyDown}
        {...aria}
      />
      <button type="button" tabIndex={-1} aria-label="Show options" disabled={disabled}
              className="absolute right-0 top-0 h-full px-3 text-bodytext hover:text-link disabled:opacity-50"
              onMouseDown={event => event.preventDefault()}
              onClick={event => { event.preventDefault(); if (open) setOpen(false); else show(); }}>
        <ChevronDown className={cn('h-4 w-4 transition-transform', open && 'rotate-180')} />
      </button>
      {open && rows.length > 0 && (
        <ul ref={list} id={listId} role="listbox" aria-multiselectable={multiple || undefined}
            className="absolute z-50 mt-1 max-h-60 w-full overflow-y-auto rounded-xl border border-border bg-card p-1 shadow-lg [scrollbar-width:thin] [scrollbar-color:var(--border)_transparent]">
          {rows.map((option, index) => {
            const selected = !option.isNew && option.value.toLowerCase() === current;
            return (
              <li key={(option.isNew ? 'new:' : '') + option.value} id={`${listId}-${index}`} role="option" aria-selected={selected}
                  className={cn('cursor-pointer rounded-lg px-3 py-2 text-sm text-link',
                    index === active ? 'bg-lightprimary text-primary' : 'hover:bg-lightgray',
                    selected && 'font-semibold',
                    option.isNew && 'flex items-center gap-2 border-t border-border mt-1 text-primary')}
                  onMouseDown={event => event.preventDefault()}
                  onMouseEnter={() => setActive(index)}
                  onClick={event => { event.preventDefault(); pick(option.value); }}>
                {option.isNew ? <><Plus className="h-4 w-4" /> Add “{option.value}” as a new {newLabel}</> : option.value}
                {option.hint && <span className="block text-xs text-bodytext font-normal">{option.hint}</span>}
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
