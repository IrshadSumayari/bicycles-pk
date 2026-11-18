import {Input}from'@/components/ui/input';
import { useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useApp } from '../../context/SupabaseAppContext';
import { webCatalogService, type WebCollection } from '../../lib/services';
import { queryKeys } from '../../lib/queryClient';
import { useProductSearch } from '../../lib/hooks/useProducts';
import { resizeImage, slugify } from '../../lib/images';
import { getErrorMessage } from '../../lib/errors';
import { swalConfig } from '../../lib/sweetAlert';
import { ReportStatus } from '../reports/ReportStatus';

export function CollectionsManager() {
  const { state } = useApp();
  const allowed = ['admin', 'manager'].includes(state.currentUser?.role ?? '');
  const query = useQuery({
    queryKey: queryKeys.collections,
    queryFn: webCatalogService.collections.list,
    enabled: allowed,
  });
  const [selected, setSelected] = useState<WebCollection | 'new' | null>(null);
  if (!allowed) return null;
  if (selected)
    return (
      <CollectionEditor
        key={selected === 'new' ? 'new' : selected.id}
        initial={selected === 'new' ? null : selected}
        onBack={() => setSelected(null)}
      />
    );
  return (
    <section className="space-y-4">
      <div className="flex justify-between">
        <h2 className="text-xl font-bold">Collections</h2>
        <button
          type="button"
          className="btn btn-primary btn-md"
          onClick={() => setSelected('new')}
        >
          New collection
        </button>
      </div>
      <ReportStatus
        loading={query.isPending}
        error={query.error}
        retry={() => void query.refetch()}
      />
      {query.data?.map((collection) => (
        <button
          type="button"
          className="card p-4 w-full text-left"
          key={collection.id}
          onClick={() => setSelected(collection)}
        >
          <span className="font-semibold">{collection.name}</span> ·{' '}
          {collection.slug} · {collection.published ? 'Published' : 'Draft'}
        </button>
      ))}
      {query.data?.length === 0 && <p>No collections yet.</p>}
    </section>
  );
}

function pakistanTime(value: string | null | undefined) {
  return value
    ? new Intl.DateTimeFormat('sv-SE', {
        timeZone: 'Asia/Karachi',
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        hourCycle: 'h23',
      })
        .format(new Date(value))
        .replace(' ', 'T')
    : '';
}

function CollectionEditor({
  initial,
  onBack,
}: {
  initial: WebCollection | null;
  onBack: () => void;
}) {
  const [id, setId] = useState(initial?.id);
  const [name, setName] = useState(initial?.name ?? '');
  const [slug, setSlug] = useState(initial?.slug ?? '');
  const [description, setDescription] = useState(initial?.description ?? '');
  const [hero, setHero] = useState(initial?.hero_image_path ?? '');
  const [published, setPublished] = useState(initial?.published ?? false);
  const [sortOrder, setSortOrder] = useState(initial?.sort_order ?? 0);
  const [starts, setStarts] = useState(pakistanTime(initial?.starts_at));
  const [ends, setEnds] = useState(pakistanTime(initial?.ends_at));
  const [busy, setBusy] = useState(false);
  const [q, setQ] = useState('');
  const [chosen, setChosen] = useState<{ id: string; name: string }[] | null>(
    null,
  );
  const action = useRef<{
    fingerprint: string;
    detailsId: string;
    stylesId: string;
    savedId?: string;
  } | null>(null);
  const members = useQuery({
    queryKey: queryKeys.collectionStyles(id ?? ''),
    queryFn: () => webCatalogService.collections.listStyles(id!),
    enabled: !!id,
  });
  const search = useProductSearch({ q, limit: 30 }, !!q.trim());
  const styles =
    chosen ??
    members.data?.map((row) => ({
      id: row.style_id,
      name: row.style?.name ?? 'Unavailable style',
    })) ??
    [];
  const results = [
    ...new Map(
      (search.data?.rows ?? []).map((row) => [
        row.styleId,
        { id: row.styleId, name: row.name },
      ]),
    ).values(),
  ];
  const valid =
    !!name.trim() &&
    /^[a-z0-9]+(-[a-z0-9]+)*$/.test(slug) &&
    (!starts || !ends || starts < ends);
  async function save() {
    if (!valid || busy) return;
    setBusy(true);
    try {
      const value = {
        slug,
        name,
        description: description || null,
        hero_image_path: hero || null,
        published,
        sort_order: sortOrder,
        starts_at: starts ? new Date(starts + '+05:00').toISOString() : null,
        ends_at: ends ? new Date(ends + '+05:00').toISOString() : null,
      };
      const fingerprint = JSON.stringify([
        value,
        styles.map((style) => style.id),
      ]);
      if (action.current?.fingerprint !== fingerprint)
        action.current = {
          fingerprint,
          detailsId: crypto.randomUUID(),
          stylesId: crypto.randomUUID(),
          savedId: id,
        };
      const pending = action.current;
      const saved = await webCatalogService.collections.save(
        { ...value, id: pending.savedId },
        pending.detailsId,
      );
      pending.savedId = saved.id;
      setId(saved.id);
      await webCatalogService.collections.setStyles(
        saved.id,
        styles.map((style) => style.id),
        pending.stylesId,
      );
      action.current = null;
      swalConfig.success('Collection saved');
    } catch (error) {
      swalConfig.error(getErrorMessage(error));
    } finally {
      setBusy(false);
    }
  }
  async function upload(file?: File) {
    if (!file || !id) return;
    setBusy(true);
    try {
      setHero(
        await webCatalogService.collections.uploadHero(
          id,
          await resizeImage(file),
        ),
      );
    } catch (error) {
      swalConfig.error(getErrorMessage(error));
    } finally {
      setBusy(false);
    }
  }
  function move(index: number, delta: number) {
    const next = [...styles];
    [next[index], next[index + delta]] = [next[index + delta], next[index]];
    setChosen(next);
  }
  return (
    <section className="card p-5 space-y-4" aria-label="Collection editor">
      <button
        type="button"
        className="btn btn-secondary btn-sm"
        disabled={busy}
        onClick={onBack}
      >
        All collections
      </button>
      <h2 className="text-xl font-bold">
        {initial ? 'Edit collection' : 'New collection'}
      </h2>
      <fieldset disabled={busy} className="space-y-3">
        <label className="block">
          Collection name
          <Input
            className="input block"
            value={name}
            onChange={(event) => {
              setName(event.target.value);
              if (!slug || slug === slugify(name))
                setSlug(slugify(event.target.value));
            }}
          />
        </label>
        <label className="block">
          Collection web address
          <Input
            className="input block"
            value={slug}
            onChange={(event) => setSlug(event.target.value)}
            aria-invalid={!!slug && !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(slug)}
          />
        </label>
        <label className="block">
          Collection description
          <textarea
            aria-label="Collection description"
            className="textarea block"
            value={description}
            onChange={(event) => setDescription(event.target.value)}
          />
        </label>
        <label className="flex gap-2">
          <Input
            type="checkbox"
            checked={published}
            onChange={(event) => setPublished(event.target.checked)}
          />
          Collection published
        </label>
        <label className="block">
          Display order
          <Input
            className="input block"
            type="number"
            step="1"
            value={sortOrder}
            onChange={(event) => setSortOrder(Number(event.target.value))}
          />
        </label>
        <p className="text-sm text-bodytext">
          Collection times are Pakistan time. Leave blank for no start or end
          limit.
        </p>
        <label className="block">
          Starts at (Pakistan time)
          <Input
            className="input block"
            type="datetime-local"
            value={starts}
            onChange={(event) => setStarts(event.target.value)}
          />
        </label>
        <label className="block">
          Ends at (Pakistan time)
          <Input
            className="input block"
            type="datetime-local"
            value={ends}
            onChange={(event) => setEnds(event.target.value)}
          />
        </label>
        {starts && ends && starts >= ends && (
          <p role="alert" className="text-error">
            The end must be after the start.
          </p>
        )}
        <label className="block">
          Hero image
          <Input
            className="input block"
            type="file"
            accept="image/*"
            disabled={!id}
            onChange={(event) => {
              void upload(event.target.files?.[0]);
              event.target.value = '';
            }}
          />
        </label>
        {!id && (
          <p className="text-sm text-bodytext">
            Save the collection first to upload a hero image.
          </p>
        )}
        {hero && (
          <>
            <img
              className="h-36 rounded-xl"
              src={webCatalogService.publicUrl(hero)}
              alt={name}
            />
            <button
              type="button"
              className="btn btn-secondary btn-sm"
              onClick={() => setHero('')}
            >
              Remove hero from collection
            </button>
          </>
        )}
        <label className="block">
          Find styles
          <Input
            className="input block"
            placeholder="Search styles by name or SKU"
            value={q}
            onChange={(event) => setQ(event.target.value)}
          />
        </label>
        <ReportStatus
          loading={search.isFetching || (!!id && members.isPending)}
          error={search.error ?? members.error}
          retry={() => {
            void search.refetch();
            if (id) void members.refetch();
          }}
        />
        {q.trim() &&
          results.map((style) => (
            <button
              type="button"
              className="btn btn-secondary btn-sm mr-2"
              disabled={styles.some((item) => item.id === style.id)}
              key={style.id}
              onClick={() => setChosen([...styles, style])}
            >
              Add {style.name}
            </button>
          ))}
        {!!q.trim() && !search.searching && !results.length && (
          <p>No matching styles</p>
        )}
        <ol className="space-y-2">
          {styles.map((style, index) => (
            <li
              className="border p-3 rounded-xl flex flex-wrap gap-2 items-center"
              key={style.id}
            >
              <span className="flex-1">{style.name}</span>
              <button
                type="button"
                className="btn btn-secondary btn-sm"
                disabled={index === 0}
                onClick={() => move(index, -1)}
                aria-label={`Move ${style.name} up`}
              >
                Up
              </button>
              <button
                type="button"
                className="btn btn-secondary btn-sm"
                disabled={index === styles.length - 1}
                onClick={() => move(index, 1)}
                aria-label={`Move ${style.name} down`}
              >
                Down
              </button>
              <button
                type="button"
                className="btn btn-secondary btn-sm"
                onClick={() =>
                  setChosen(styles.filter((item) => item.id !== style.id))
                }
              >
                Remove {style.name}
              </button>
            </li>
          ))}
        </ol>
        <button
          type="button"
          className="btn btn-primary btn-md"
          disabled={!valid || !!(id && (members.isPending || members.error))}
          onClick={() => void save()}
        >
          {busy ? 'Saving…' : 'Save collection'}
        </button>
      </fieldset>
    </section>
  );
}
