// three.js scene for the 360° try-on viewer. Loaded on demand by
// components/try-on-viewer.tsx, so product pages without the viewer open
// never download three.js.
import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { RoomEnvironment } from "three/examples/jsm/environments/RoomEnvironment.js";
import { isGarmentMaterial } from "../../shared/tryOn";

export type SceneOptions = {
  modelUrl: string;
  garmentMaterials?: string[];
  color: string;
  tone?: string;
  autoRotate: boolean;
  // Called with the skin tones the model offers (from Skin_<tone> materials).
  onReady: (tones: string[]) => void;
  onError: (message: string) => void;
  onInteract: () => void;
};
export type TryOnScene = {
  setColor: (hex: string) => void;
  setTone: (tone: string) => void;
  setAutoRotate: (on: boolean) => void;
  turn: (radians: number) => void;
  reset: () => void;
  dispose: () => void;
};
const HEIGHT = 1.72;
const TARGET = new THREE.Vector3(0, 0.98, 0);
const HOME = new THREE.Vector3(0, 1.08, 3.6);
const SKIN = /^Skin_(\w+)$/i;

export function createTryOnScene(
  container: HTMLElement,
  options: SceneOptions,
): TryOnScene {
  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;
  renderer.domElement.style.touchAction = "none";
  container.appendChild(renderer.domElement);

  const scene = new THREE.Scene();
  const pmrem = new THREE.PMREMGenerator(renderer);
  const room = new RoomEnvironment();
  scene.environment = pmrem.fromScene(room, 0.04).texture;
  room.dispose();
  const key = new THREE.DirectionalLight("#fff4ea", 1.6);
  key.position.set(1.6, 2.6, 2.2);
  const rim = new THREE.DirectionalLight("#f3d6e4", 0.9);
  rim.position.set(-2, 1.8, -2.2);
  scene.add(key, rim, new THREE.HemisphereLight("#fff8f2", "#d9c4c4", 0.35));
  scene.add(floorShadow());

  const camera = new THREE.PerspectiveCamera(28, 1, 0.05, 50);
  camera.position.copy(HOME);
  const controls = new OrbitControls(camera, renderer.domElement);
  controls.target.copy(TARGET);
  controls.enablePan = false;
  controls.enableDamping = true;
  controls.dampingFactor = 0.08;
  controls.minDistance = 1.4;
  controls.maxDistance = 5;
  controls.minPolarAngle = Math.PI * 0.32;
  controls.maxPolarAngle = Math.PI * 0.6;
  controls.autoRotate = options.autoRotate;
  controls.autoRotateSpeed = 1.6;
  controls.addEventListener("start", options.onInteract);
  controls.update();

  const garments: THREE.MeshStandardMaterial[] = [];
  const disposables: { dispose: () => void }[] = [];
  let color = options.color;
  const paint = () => garments.forEach((m) => m.color.set(color));
  // A model can carry one skin material per tone; only the one in use is
  // applied, the others load (with their textures) when first chosen.
  const skinMeshes: THREE.Mesh[] = [];
  let tone = options.tone;
  let dress = () => {};
  const figure = new THREE.Group();
  scene.add(figure);

  new GLTFLoader().load(
    options.modelUrl,
    (gltf) => {
      const model = gltf.scene;
      const box = new THREE.Box3().setFromObject(model);
      const size = box.getSize(new THREE.Vector3());
      const scale = HEIGHT / (size.y || 1);
      model.scale.setScalar(scale);
      const centre = box.getCenter(new THREE.Vector3()).multiplyScalar(scale);
      model.position.set(-centre.x, -box.min.y * scale, -centre.z);
      model.traverse((node) => {
        if (!(node instanceof THREE.Mesh)) return;
        const list = Array.isArray(node.material)
          ? node.material
          : [node.material];
        if (list.length === 1 && SKIN.test(list[0].name)) skinMeshes.push(node);
        const next = list.map((material: THREE.Material) => {
          disposables.push(material);
          if (
            !isGarmentMaterial(
              material.name || node.name,
              options.garmentMaterials,
            ) ||
            !(material instanceof THREE.MeshStandardMaterial)
          )
            return material;
          // A copy keeps the model's textures while taking the shade.
          const fabric = material.clone();
          garments.push(fabric);
          disposables.push(fabric);
          return fabric;
        });
        node.material = Array.isArray(node.material) ? next : next[0];
        disposables.push(node.geometry);
      });
      figure.add(model);
      paint();
      const skins = new Map<string, number>();
      const defs: { name?: string }[] = gltf.parser.json.materials ?? [];
      defs.forEach((m, i) => {
        const id = SKIN.exec(m.name ?? "")?.[1];
        if (id) skins.set(id.toLowerCase(), i);
      });
      dress = () => {
        const wanted = tone;
        const index = wanted ? skins.get(wanted) : undefined;
        if (index === undefined || !skinMeshes.length) return;
        void gltf.parser
          .getDependency("material", index)
          .then((skin: THREE.Material) => {
            if (tone !== wanted) return;
            if (!disposables.includes(skin)) disposables.push(skin);
            skinMeshes.forEach((n) => (n.material = skin));
          });
      };
      dress();
      options.onReady(skinMeshes.length ? [...skins.keys()] : []);
    },
    undefined,
    () => options.onError("The 3D model could not be loaded."),
  );

  const resize = () => {
    const { clientWidth: w, clientHeight: h } = container;
    if (!w || !h) return;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  };
  const observer = new ResizeObserver(resize);
  observer.observe(container);
  resize();
  renderer.setAnimationLoop(() => {
    controls.update();
    renderer.render(scene, camera);
  });

  return {
    setColor(hex) {
      color = hex;
      paint();
    },
    setTone(next) {
      tone = next;
      dress();
    },
    setAutoRotate(on) {
      controls.autoRotate = on;
    },
    turn(radians) {
      const offset = camera.position.clone().sub(controls.target);
      offset.applyAxisAngle(new THREE.Vector3(0, 1, 0), radians);
      camera.position.copy(controls.target).add(offset);
    },
    reset() {
      camera.position.copy(HOME);
      controls.target.copy(TARGET);
    },
    dispose() {
      // A skin still loading is dropped rather than applied to a dead scene.
      tone = undefined;
      dress = () => {};
      renderer.setAnimationLoop(null);
      observer.disconnect();
      controls.dispose();
      scene.traverse((node) => {
        if (node instanceof THREE.Mesh) node.geometry.dispose();
      });
      disposables.forEach((d) => d.dispose());
      scene.environment?.dispose();
      pmrem.dispose();
      renderer.dispose();
      renderer.domElement.remove();
    },
  };
}

function floorShadow() {
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = 128;
  const ctx = canvas.getContext("2d")!;
  const g = ctx.createRadialGradient(64, 64, 0, 64, 64, 64);
  g.addColorStop(0, "rgba(60,30,40,0.28)");
  g.addColorStop(1, "rgba(60,30,40,0)");
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 128, 128);
  const plane = new THREE.Mesh(
    new THREE.PlaneGeometry(1.1, 1.1),
    new THREE.MeshBasicMaterial({
      map: new THREE.CanvasTexture(canvas),
      transparent: true,
      depthWrite: false,
    }),
  );
  plane.rotation.x = -Math.PI / 2;
  plane.position.y = 0.002;
  return plane;
}
