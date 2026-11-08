"use client";
import {
  colorHex,
  modelTones,
  spinFor,
  tonesFor,
  type ModelTone,
  type TryOn,
} from "../../shared/tryOn";
import { imageUrl, modelUrl } from "@/lib/helpers";
import type { TryOnScene } from "@/lib/try-on-scene";
import Image from "next/image";
import { Pause, Play, RotateCcw, RotateCw, RefreshCcw } from "lucide-react";
import {
  useEffect,
  useRef,
  useState,
  useSyncExternalStore,
  type CSSProperties,
} from "react";
import { Button } from "./ui/button";

type Swatch = { value: string; available: boolean };
const FALLBACK = "#c98a9b";
// Each frame of a turntable stays this long, with a short blend between
// frames, so the model turns slowly and smoothly.
const TURN_FRAME_MS = 180;
const reducedMotion = () =>
  typeof window !== "undefined" &&
  window.matchMedia("(prefers-reduced-motion: reduce)").matches;

// The shopper's model skin tone is remembered on this device, so every
// product opens on the same model. Storage can be blocked, so it is optional.
const TONE_KEY = "lv-model-tone";
const toneListeners = new Set<() => void>();
function readTone() {
  try {
    return localStorage.getItem(TONE_KEY);
  } catch {
    return null;
  }
}
function saveTone(tone: ModelTone) {
  try {
    localStorage.setItem(TONE_KEY, tone);
  } catch {}
  toneListeners.forEach((l) => l());
}
function subscribeTone(listener: () => void) {
  toneListeners.add(listener);
  window.addEventListener("storage", listener);
  return () => {
    toneListeners.delete(listener);
    window.removeEventListener("storage", listener);
  };
}

export function TryOnViewer({
  title,
  tryOn,
  swatches,
  color,
  disabled,
  onColor,
}: {
  title: string;
  tryOn: TryOn;
  swatches: Swatch[];
  color: string;
  disabled?: boolean;
  onColor: (value: string) => void;
}) {
  const preferred = useSyncExternalStore(subscribeTone, readTone, () => null);
  // Tones of the 3D model, as it reports them once loaded.
  const [stageTones, setStageTones] = useState<ModelTone[]>([]);
  const photoTones = tonesFor(tryOn, color);
  const photoTone = photoTones.find((t) => t === preferred) ?? photoTones[0];
  const frames = photoTone ? spinFor(tryOn, color, photoTone) : undefined;
  const hex = colorHex(color, tryOn.colors) ?? FALLBACK;
  const model = modelUrl(tryOn.model_path);
  const tones = frames ? photoTones : model ? stageTones : [];
  const tone = tones.find((t) => t === preferred) ?? tones[0];
  return (
    <div className="lv-tryon">
      {frames ? (
        <PhotoSpin
          key={color + tone}
          frames={frames}
          label={`${title} in ${color}, 360° photos`}
        />
      ) : model ? (
        <ModelStage
          // A new model starts a fresh stage, with its own loading state.
          key={model}
          modelUrl={model}
          garmentMaterials={tryOn.garment_materials}
          color={hex}
          tone={tone}
          onTones={(ids) =>
            setStageTones(
              modelTones.map((t) => t.id).filter((id) => ids.includes(id)),
            )
          }
          label={`${title}${color ? " in " + color : ""}, 360° model`}
        />
      ) : (
        <p className="lv-tryon-empty">
          The 360° view is not available in {color || "this option"} yet. Choose
          another colour or see the photos.
        </p>
      )}
      {tones.length > 1 && (
        <div
          className="lv-tryon-tones"
          role="group"
          aria-label="Choose the model's skin tone"
        >
          {modelTones
            .filter((t) => tones.includes(t.id))
            .map((t) => (
              <button
                type="button"
                key={t.id}
                className={t.id === tone ? "active" : ""}
                aria-pressed={t.id === tone}
                onClick={() => saveTone(t.id)}
              >
                <span style={{ background: t.swatch }} aria-hidden="true" />
                {t.label}
              </button>
            ))}
        </div>
      )}
      {swatches.some((s) => s.value) && (
        <div
          className="lv-tryon-swatches"
          role="group"
          aria-label="Choose a colour to see it on the model"
        >
          {swatches
            .filter((s) => s.value)
            .map((s) => {
              const shade = colorHex(s.value, tryOn.colors);
              const active = s.value === color;
              return (
                <button
                  type="button"
                  key={s.value}
                  className={active ? "active" : ""}
                  aria-pressed={active}
                  disabled={disabled || !s.available}
                  title={s.value + (s.available ? "" : " (out of stock)")}
                  aria-label={
                    "Colour: " + s.value + (s.available ? "" : ", out of stock")
                  }
                  onClick={() => onColor(s.value)}
                >
                  <span
                    style={{ background: shade ?? undefined }}
                    data-unknown={!shade || undefined}
                  >
                    {!shade && s.value.slice(0, 1).toUpperCase()}
                  </span>
                </button>
              );
            })}
        </div>
      )}
    </div>
  );
}

function ModelStage({
  modelUrl,
  garmentMaterials,
  color,
  tone,
  onTones,
  label,
}: {
  modelUrl: string;
  garmentMaterials?: string[];
  color: string;
  tone?: ModelTone;
  onTones: (tones: string[]) => void;
  label: string;
}) {
  const stage = useRef<HTMLDivElement>(null);
  const scene = useRef<TryOnScene | null>(null);
  const colorRef = useRef(color);
  const toneRef = useRef(tone);
  const onTonesRef = useRef(onTones);
  useEffect(() => {
    onTonesRef.current = onTones;
  }, [onTones]);
  const [status, setStatus] = useState<"loading" | "ready" | string>("loading");
  const [spinning, setSpinning] = useState(() => !reducedMotion());
  const spinningRef = useRef(spinning);
  const materialsKey = JSON.stringify(garmentMaterials ?? []);
  useEffect(() => {
    let cancelled = false;
    let created: TryOnScene | null = null;
    void import("@/lib/try-on-scene")
      .then(({ createTryOnScene }) => {
        if (cancelled || !stage.current) return;
        try {
          created = createTryOnScene(stage.current, {
            modelUrl,
            garmentMaterials: JSON.parse(materialsKey) as string[],
            color: colorRef.current,
            tone: toneRef.current,
            autoRotate: spinningRef.current,
            onReady: (tones) => {
              if (cancelled) return;
              setStatus("ready");
              onTonesRef.current(tones);
            },
            onError: (message) => !cancelled && setStatus(message),
            onInteract: () => {
              spinningRef.current = false;
              setSpinning(false);
              created?.setAutoRotate(false);
            },
          });
          scene.current = created;
        } catch {
          setStatus("This device cannot show 3D models. Try the photos.");
        }
      })
      .catch(() => !cancelled && setStatus("The 3D viewer could not load."));
    return () => {
      cancelled = true;
      created?.dispose();
      scene.current = null;
    };
  }, [modelUrl, materialsKey]);
  useEffect(() => {
    colorRef.current = color;
    scene.current?.setColor(color);
  }, [color]);
  useEffect(() => {
    toneRef.current = tone;
    if (tone) scene.current?.setTone(tone);
  }, [tone]);
  const toggle = () => {
    const next = !spinning;
    spinningRef.current = next;
    setSpinning(next);
    scene.current?.setAutoRotate(next);
  };
  const failed = status !== "loading" && status !== "ready";
  return (
    <>
      <div
        ref={stage}
        className="lv-tryon-stage"
        role="img"
        aria-label={label + ". Drag to rotate."}
        tabIndex={0}
        onKeyDown={(e) => {
          if (e.key === "ArrowLeft") scene.current?.turn(-0.3);
          if (e.key === "ArrowRight") scene.current?.turn(0.3);
        }}
      >
        {status === "loading" && (
          <span className="lv-tryon-status">Preparing 360° view…</span>
        )}
        {failed && (
          <span role="alert" className="lv-tryon-status">
            {status}
          </span>
        )}
      </div>
      <Controls
        disabled={status !== "ready"}
        spinning={spinning}
        onToggle={toggle}
        onTurn={(d) => scene.current?.turn(d * 0.5)}
        onReset={() => scene.current?.reset()}
      />
    </>
  );
}

function PhotoSpin({ frames, label }: { frames: string[]; label: string }) {
  const urls = frames.map((f) => imageUrl(f)).filter((u): u is string => !!u);
  const [index, setIndex] = useState(0);
  const [spinning, setSpinning] = useState(() => !reducedMotion());
  const drag = useRef<{ x: number; start: number } | null>(null);
  const count = urls.length;
  // Many photos play as a continuous turntable; a few angle photos (front,
  // side, back…) fade from one to the next more slowly.
  const turntable = count >= 16;
  const step = (n: number) =>
    setIndex((i) => (((i + n) % count) + count) % count);
  useEffect(() => {
    if (!spinning || count < 2) return;
    const timer = setInterval(
      () => setIndex((i) => (i + 1) % count),
      turntable ? TURN_FRAME_MS : 1500,
    );
    return () => clearInterval(timer);
  }, [spinning, count, turntable]);
  if (!count) return null;
  return (
    <>
      <div
        className="lv-tryon-stage"
        style={{ "--lv-spin-fade": turntable ? "0.18s" : "0.5s" } as CSSProperties}
        role="img"
        aria-label={label + ". Drag to rotate."}
        tabIndex={0}
        onKeyDown={(e) => {
          if (e.key === "ArrowLeft") step(-1);
          if (e.key === "ArrowRight") step(1);
        }}
        onPointerDown={(e) => {
          setSpinning(false);
          drag.current = { x: e.clientX, start: index };
          e.currentTarget.setPointerCapture(e.pointerId);
        }}
        onPointerMove={(e) => {
          if (!drag.current) return;
          const width = e.currentTarget.clientWidth || 1;
          // A frame per 10px at most, so a short drag is a gentle turn.
          const moved = Math.round(
            (e.clientX - drag.current.x) / Math.max(width / count, 10),
          );
          setIndex((((drag.current.start - moved) % count) + count) % count);
        }}
        onPointerUp={() => (drag.current = null)}
        onPointerCancel={() => (drag.current = null)}
      >
        {urls.map((url, i) => (
          <Image
            key={url + i}
            src={url}
            alt=""
            fill
            unoptimized
            draggable={false}
            loading="eager"
            data-active={i === index || undefined}
            sizes="(max-width:760px) 100vw,560px"
          />
        ))}
      </div>
      <Controls
        spinning={spinning}
        onToggle={() => setSpinning(!spinning)}
        onTurn={(d) => step(d * Math.max(1, Math.round(count / 12)))}
        onReset={() => setIndex(0)}
      />
    </>
  );
}

function Controls({
  disabled,
  spinning,
  onToggle,
  onTurn,
  onReset,
}: {
  disabled?: boolean;
  spinning: boolean;
  onToggle: () => void;
  onTurn: (direction: 1 | -1) => void;
  onReset: () => void;
}) {
  return (
    <div className="lv-tryon-controls" aria-label="360° view controls">
      <Button
        variant="ghost"
        size="icon"
        disabled={disabled}
        aria-label="Rotate left"
        onClick={() => onTurn(-1)}
      >
        <RotateCcw size={18} />
      </Button>
      <Button
        variant="ghost"
        size="icon"
        disabled={disabled}
        aria-label={spinning ? "Stop rotating" : "Rotate automatically"}
        aria-pressed={spinning}
        onClick={onToggle}
      >
        {spinning ? <Pause size={18} /> : <Play size={18} />}
      </Button>
      <Button
        variant="ghost"
        size="icon"
        disabled={disabled}
        aria-label="Rotate right"
        onClick={() => onTurn(1)}
      >
        <RotateCw size={18} />
      </Button>
      <Button
        variant="ghost"
        size="icon"
        disabled={disabled}
        aria-label="Reset view"
        onClick={onReset}
      >
        <RefreshCcw size={18} />
      </Button>
      <span className="muted">Drag to turn 360°</span>
    </div>
  );
}
