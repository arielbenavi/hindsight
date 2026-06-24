import { useCallback, useEffect, useState } from "react";
import { CATEGORIES, SOURCES, type Item, type Source } from "./types";

const API = (import.meta.env.VITE_API_URL as string | undefined) || "http://localhost:8000";

export default function App() {
  const [items, setItems] = useState<Item[]>([]);
  const [category, setCategory] = useState<string>("");
  const [source, setSource] = useState<string>("");
  const [q, setQ] = useState<string>("");
  const [debouncedQ, setDebouncedQ] = useState<string>("");
  const [loading, setLoading] = useState<boolean>(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    const t = setTimeout(() => setDebouncedQ(q), 250);
    return () => clearTimeout(t);
  }, [q]);

  const refetch = useCallback(async () => {
    setLoading(true);
    setErr(null);
    const params = new URLSearchParams();
    if (category) params.set("category", category);
    if (source) params.set("source", source);
    if (debouncedQ) params.set("q", debouncedQ);
    try {
      const r = await fetch(`${API}/items?${params.toString()}`);
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      setItems(await r.json());
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [category, source, debouncedQ]);

  useEffect(() => {
    refetch();
  }, [refetch]);

  useEffect(() => {
    const t = setInterval(refetch, 15000);
    return () => clearInterval(t);
  }, [refetch]);

  const onRetry = async (id: number) => {
    try {
      await fetch(`${API}/items/${id}/retry`, { method: "POST" });
      refetch();
    } catch (e) {
      console.error("retry failed", e);
    }
  };

  return (
    <div className="min-h-full">
      <header className="sticky top-0 z-10 bg-stone-50/90 dark:bg-stone-950/90 backdrop-blur border-b border-stone-200 dark:border-stone-800">
        <div className="max-w-2xl mx-auto px-3 py-2.5 space-y-2">
          <div className="flex items-center gap-2">
            <h1 className="text-sm font-semibold text-stone-700 dark:text-stone-300">
              savefeed
            </h1>
            <span className="text-xs text-stone-400">
              {loading ? "…" : `${items.length} item${items.length === 1 ? "" : "s"}`}
            </span>
            <button
              onClick={refetch}
              className="ml-auto text-xs text-stone-500 hover:text-stone-900 dark:hover:text-stone-100 px-2 py-1 rounded hover:bg-stone-100 dark:hover:bg-stone-800"
            >
              ↻ refresh
            </button>
          </div>

          <input
            type="search"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="search summary, transcript, on-screen text…"
            className="w-full px-3 py-2 rounded-md border border-stone-300 dark:border-stone-700 bg-white dark:bg-stone-900 text-sm focus:outline-none focus:ring-2 focus:ring-stone-400 dark:text-stone-100"
          />

          <PillRow label="cat" options={CATEGORIES} value={category} onChange={setCategory} />
          <PillRow label="src" options={SOURCES} value={source} onChange={setSource} />

          {err && (
            <p className="text-xs text-red-600 dark:text-red-400">
              api error: {err} — is uvicorn running on {API}?
            </p>
          )}
        </div>
      </header>

      <main className="max-w-2xl mx-auto px-3 py-3 space-y-2.5">
        {items.map((item) => (
          <Card key={item.id} item={item} onRetry={onRetry} />
        ))}
        {!loading && items.length === 0 && !err && (
          <p className="text-stone-400 text-sm text-center py-8">
            nothing matches these filters.
          </p>
        )}
      </main>
    </div>
  );
}

type PillRowProps = {
  label: string;
  options: readonly string[];
  value: string;
  onChange: (v: string) => void;
};

function PillRow({ label, options, value, onChange }: PillRowProps) {
  return (
    <div className="flex items-center gap-1 overflow-x-auto text-xs -mx-1 px-1">
      <span className="text-stone-400 mr-1 shrink-0">{label}</span>
      <Pill active={!value} onClick={() => onChange("")}>
        all
      </Pill>
      {options.map((opt) => (
        <Pill key={opt} active={opt === value} onClick={() => onChange(opt)}>
          {opt}
        </Pill>
      ))}
    </div>
  );
}

function Pill({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      className={
        "px-2.5 py-0.5 rounded-full whitespace-nowrap font-mono text-[11px] transition " +
        (active
          ? "bg-stone-900 text-stone-100 dark:bg-stone-100 dark:text-stone-900"
          : "bg-stone-100 dark:bg-stone-800 text-stone-600 dark:text-stone-300 hover:bg-stone-200 dark:hover:bg-stone-700")
      }
    >
      {children}
    </button>
  );
}

function Card({ item, onRetry }: { item: Item; onRetry: (id: number) => void }) {
  const failed = item.status === "failed";
  const pending = item.status === "pending";
  const preview =
    item.on_screen_text?.trim() ||
    item.key_takeaways?.slice(0, 3).map((t) => `• ${t}`).join("\n") ||
    "";

  return (
    <article className="rounded-lg bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-800 p-3 shadow-sm">
      <div className="flex items-center gap-1.5 text-xs mb-1.5 flex-wrap">
        <Chip>{labelForSource(item.source)}</Chip>
        {item.category && <Chip>{item.category}</Chip>}
        {failed && (
          <Chip className="bg-red-100 dark:bg-red-950 text-red-700 dark:text-red-300">
            failed
          </Chip>
        )}
        {pending && (
          <Chip className="bg-amber-100 dark:bg-amber-950 text-amber-800 dark:text-amber-300">
            pending
          </Chip>
        )}
        <span className="ml-auto text-stone-400 shrink-0">
          {relativeTime(item.saved_at)}
        </span>
      </div>

      {item.summary && (
        <h2 className="text-[15px] leading-snug text-stone-900 dark:text-stone-100 font-medium mb-1.5 line-clamp-4">
          {item.summary}
        </h2>
      )}

      {preview && (
        <p className="text-sm text-stone-500 dark:text-stone-400 mb-2 line-clamp-3 whitespace-pre-wrap">
          {preview}
        </p>
      )}

      <div className="flex items-center gap-3 text-xs pt-1">
        {item.source_url && (
          <a
            href={item.source_url}
            target="_blank"
            rel="noopener noreferrer"
            className="text-stone-600 dark:text-stone-300 hover:text-stone-900 dark:hover:text-stone-100"
          >
            ↗ open original
          </a>
        )}
        <a
          href={`${API}/items/${item.id}/pretty`}
          target="_blank"
          rel="noopener noreferrer"
          className="text-stone-600 dark:text-stone-300 hover:text-stone-900 dark:hover:text-stone-100"
        >
          details →
        </a>
        {failed && (
          <button
            onClick={() => onRetry(item.id)}
            className="ml-auto text-red-600 dark:text-red-400 hover:text-red-800 dark:hover:text-red-200"
          >
            ↻ retry
          </button>
        )}
      </div>
    </article>
  );
}

function Chip({
  children,
  className = "",
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <span
      className={
        "px-2 py-0.5 rounded-full font-mono text-[11px] " +
        (className ||
          "bg-stone-100 dark:bg-stone-800 text-stone-700 dark:text-stone-300")
      }
    >
      {children}
    </span>
  );
}

function labelForSource(s: Source): string {
  return s === "ig_reel" ? "ig" : s;
}

function relativeTime(iso: string): string {
  const d = new Date(iso);
  const diff = (Date.now() - d.getTime()) / 1000;
  if (diff < 60) return "now";
  if (diff < 3600) return `${Math.floor(diff / 60)}m`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h`;
  if (diff < 7 * 86400) return `${Math.floor(diff / 86400)}d`;
  return d.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}
