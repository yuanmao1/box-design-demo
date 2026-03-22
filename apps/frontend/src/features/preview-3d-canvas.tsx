import { OrbitControls } from "@react-three/drei";
import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { useEffect, useMemo, useRef, useState } from "react";
import {
  ACESFilmicToneMapping,
  BufferGeometry,
  ClampToEdgeWrapping,
  CanvasTexture,
  DoubleSide,
  ExtrudeGeometry,
  Float32BufferAttribute,
  LinearFilter,
  Line as ThreeLine,
  LineBasicMaterial,
  Matrix4,
  MeshBasicMaterial,
  PerspectiveCamera,
  ShapeGeometry,
  SRGBColorSpace,
  Vector3,
} from "three";
import { pathToShape } from "@/lib/geometry";
import { loadPanelTextureCanvas } from "@/lib/panel-texture";
import { pathBounds } from "@/lib/geometry";
import {
  applyExtrudedUv,
  applySurfaceFrameUv,
  buildPreviewSceneData,
  fallbackSurfaceFrame,
  type PreviewSceneData,
} from "@/lib/preview-3d";
import { log3DDebug } from "@/lib/debug-3d";
import type { GeneratedPackage } from "@/types/api";

export function Preview3DCanvas({
  result,
  focusPanelId,
}: {
  result: GeneratedPackage["preview_3d"] | null;
  focusPanelId?: { panelId: number; seq: number } | null;
}) {
  const sceneData = useMemo(() => buildPreviewSceneData(result), [result]);

  if (!result || !sceneData) {
    return <EmptyState label="Loading folding graph from wasm export..." />;
  }

  return (
    <div className="relative h-[520px] overflow-hidden rounded-[1.5rem] border border-border bg-[radial-gradient(circle_at_top,#f8fbfd,#dbe5ec)]">
      <Canvas
        camera={{ position: [140, -160, 140], fov: 32 }}
        className="relative"
        dpr={[1, 2]}
        frameloop="demand"
        gl={async (defaultProps) => {
          const { WebGPURenderer } = await import("three/webgpu");
          const renderer = new WebGPURenderer({
            canvas: defaultProps.canvas as HTMLCanvasElement,
            alpha: true,
            antialias: true,
            powerPreference: "high-performance",
          });
          renderer.outputColorSpace = SRGBColorSpace;
          renderer.toneMapping = ACESFilmicToneMapping;
          await renderer.init();
          return renderer;
        }}
      >
        <color attach="background" args={["#e7eef2"]} />
        <ambientLight intensity={0.9} />
        <hemisphereLight
          color="#ffffff"
          groundColor="#b8c5cf"
          intensity={1.05}
          position={[0, 0, 180]}
        />
        <directionalLight intensity={1.4} position={[180, -140, 220]} />
        <directionalLight intensity={0.5} position={[-120, 160, 80]} />
        <SceneGrid radius={sceneData.radius} centerZ={-sceneData.center.z} />
        <CameraRig center={sceneData.center} radius={sceneData.radius} focusPanelId={focusPanelId ?? null} sceneData={sceneData} />
        <group
          position={[
            -sceneData.center.x,
            -sceneData.center.y,
            -sceneData.center.z,
          ]}
        >
          {sceneData.nodes.map((sceneNode) => (
            <PanelNode key={sceneNode.index} sceneNode={sceneNode} thickness={sceneData.thickness} />
          ))}
        </group>
      </Canvas>
    </div>
  );
}

function PanelNode({
  sceneNode,
  thickness,
}: {
  sceneNode: NonNullable<ReturnType<typeof buildPreviewSceneData>>["nodes"][number];
  thickness: number;
}) {
  const useExtrude = thickness > 0;

  const frame = useMemo(() => {
    if (sceneNode.node.surface_frame) return sceneNode.node.surface_frame;
    return sceneNode.node.boundary
      ? fallbackSurfaceFrame(sceneNode.node.boundary)
      : null;
  }, [sceneNode.node.boundary, sceneNode.node.surface_frame]);

  const geometry = useMemo(() => {
    if (!sceneNode.node.boundary || !frame) return null;
    const shape = pathToShape(sceneNode.node.boundary);

    if (!useExtrude) {
      const indexedGeometry = new ShapeGeometry(shape);
      const nextGeometry = indexedGeometry.toNonIndexed();
      indexedGeometry.dispose();
      applySurfaceFrameUv(nextGeometry, frame);
      nextGeometry.computeVertexNormals();
      return nextGeometry;
    }

    // Extruded geometry for thick panels
    // ExtrudeGeometry extrudes from Z=0 along +Z. The front cap at Z=0 has
    // normal {0,0,-1}. If the panel's outside_normal.z > 0 (outside faces +Z),
    // the outer surface is the back cap — translate so it lands at Z=0.
    const nz = sceneNode.node.outside_normal?.z ?? -1;
    const indexed = new ExtrudeGeometry(shape, {
      depth: thickness,
      bevelEnabled: false,
    });
    if (nz > 0) {
      indexed.translate(0, 0, -thickness);
    }
    const extruded = indexed.toNonIndexed();
    indexed.dispose();
    applyExtrudedUv(extruded, frame);
    extruded.computeVertexNormals();
    // Assign material groups by face normal: cap faces (|nz|>0.5) = group 0, side faces = group 1
    assignExtrudeMaterialGroups(extruded);
    return extruded;
  }, [frame, sceneNode.node.boundary, thickness, useExtrude]);

  const outlineGeometry = useMemo(
    () => buildOutlineGeometry(sceneNode.outlinePoints),
    [sceneNode.outlinePoints],
  );
  const outline = useMemo(() => {
    if (!outlineGeometry) return null;

    const material = new LineBasicMaterial({
      color: "#9a5a14",
      opacity: 0.82,
      transparent: true,
      toneMapped: false,
    });
    const line = new ThreeLine(outlineGeometry, material);
    line.matrix.copy(sceneNode.worldMatrix);
    line.matrixAutoUpdate = false;
    line.renderOrder = 3;
    return line;
  }, [outlineGeometry, sceneNode.worldMatrix]);
  const texture = usePanelTexture(sceneNode);

  const materials = useMemo(() => {
    if (!useExtrude) return null;
    // ExtrudeGeometry groups: materialIndex 0 = caps (front+back), materialIndex 1 = sides
    const capMaterial = new MeshBasicMaterial({
      color: "#ffffff",
      map: texture ?? null,
      side: DoubleSide,
      toneMapped: false,
    });
    const sideMaterial = new MeshBasicMaterial({
      color: "#c4a86a",
      side: DoubleSide,
      toneMapped: false,
    });
    return [capMaterial, sideMaterial];
  }, [texture, useExtrude]);

  useEffect(() => {
    if (!geometry || !frame) return;

    log3DDebug(`panel ${sceneNode.node.panel_id ?? "unknown"} mesh`, {
      geometry: summarizeGeometry(geometry),
      uvRange: summarizeUvRange(geometry),
      hasTexture: Boolean(texture),
      textureImage: texture?.image
        ? {
            width: texture.image.width,
            height: texture.image.height,
          }
        : null,
    });
  }, [frame, geometry, sceneNode, texture]);

  if (!geometry) return null;

  return (
    <>
      <mesh
        key={`panel-mesh-${sceneNode.index}-${texture?.uuid ?? "empty"}`}
        dispose={null}
        geometry={geometry}
        matrix={sceneNode.worldMatrix}
        matrixAutoUpdate={false}
        material={useExtrude ? materials ?? undefined : undefined}
        renderOrder={1}
      >
        {!useExtrude && (
          <meshBasicMaterial
            key={`panel-material-${sceneNode.index}-${texture?.uuid ?? "empty"}`}
            color="#ffffff"
            map={texture ?? null}
            needsUpdate
            side={DoubleSide}
            toneMapped={false}
          />
        )}
      </mesh>
      {outline ? <primitive dispose={null} object={outline} /> : null}
    </>
  );
}

function CameraRig({
  center,
  radius,
  focusPanelId,
  sceneData,
}: {
  center: { x: number; y: number; z: number };
  radius: number;
  focusPanelId: { panelId: number; seq: number } | null;
  sceneData: PreviewSceneData;
}) {
  const controlsRef = useRef<any>(null);
  const camera = useThree((state) => state.camera as PerspectiveCamera);
  const invalidate = useThree((state) => state.invalidate);
  const animRef = useRef<{
    startPos: Vector3;
    endPos: Vector3;
    startTarget: Vector3;
    endTarget: Vector3;
    progress: number;
  } | null>(null);

  useEffect(() => {
    const fitRadius = Math.max(radius, 8);
    const distance = fitRadius * 2.35;

    camera.near = Math.max(0.1, fitRadius / 40);
    camera.far = Math.max(400, distance * 10);
    camera.position.set(
      center.x + distance * 0.9,
      center.y - distance * 0.82,
      center.z + distance * 0.68,
    );
    camera.lookAt(center.x, center.y, center.z);
    camera.updateProjectionMatrix();

    if (controlsRef.current) {
      controlsRef.current.target.set(center.x, center.y, center.z);
      controlsRef.current.update();
    }

    invalidate();
  }, [camera, center.x, center.y, center.z, invalidate, radius]);

  // Keyboard pan: WASD / arrow keys
  const keysPressed = useRef(new Set<string>());
  const canvasEl = useThree((s) => s.gl.domElement);

  useEffect(() => {
    const parent = canvasEl.parentElement;
    if (!parent) return;
    // Make the container focusable so it can receive key events
    if (!parent.hasAttribute("tabindex")) parent.setAttribute("tabindex", "0");
    parent.style.outline = "none";

    const onKeyDown = (e: KeyboardEvent) => {
      const key = e.key.toLowerCase();
      if (["w", "a", "s", "d", "arrowup", "arrowdown", "arrowleft", "arrowright"].includes(key)) {
        e.preventDefault();
        keysPressed.current.add(key);
        invalidate();
      }
    };
    const onKeyUp = (e: KeyboardEvent) => {
      keysPressed.current.delete(e.key.toLowerCase());
    };
    parent.addEventListener("keydown", onKeyDown);
    parent.addEventListener("keyup", onKeyUp);
    // Focus on pointer enter so keys work without extra clicking
    const onEnter = () => parent.focus();
    parent.addEventListener("pointerenter", onEnter);
    return () => {
      parent.removeEventListener("keydown", onKeyDown);
      parent.removeEventListener("keyup", onKeyUp);
      parent.removeEventListener("pointerenter", onEnter);
    };
  }, [canvasEl, invalidate]);

  useEffect(() => {
    if (focusPanelId == null) return;
    const targetNode = sceneData.nodes.find(
      (n) => n.node.panel_id === focusPanelId.panelId,
    );
    if (!targetNode?.node.boundary) return;

    const bounds = pathBounds(targetNode.node.boundary);
    const localCenter = new Vector3(
      (bounds.minX + bounds.maxX) / 2,
      (bounds.minY + bounds.maxY) / 2,
      0,
    );
    const panelWorldCenter = localCenter.applyMatrix4(targetNode.worldMatrix);

    // Apply scene centering offset (matches the group position={[-center.x, ...]}）
    const centeredTarget = new Vector3(
      panelWorldCenter.x - sceneData.center.x,
      panelWorldCenter.y - sceneData.center.y,
      panelWorldCenter.z - sceneData.center.z,
    );

    // Get world-space normal from outside_normal
    let normal: Vector3;
    if (targetNode.node.outside_normal) {
      const n = targetNode.node.outside_normal;
      normal = new Vector3(n.x, n.y, n.z);
      const rotMatrix = new Matrix4().extractRotation(targetNode.worldMatrix);
      normal.applyMatrix4(rotMatrix).normalize();
    } else {
      normal = new Vector3(0, 0, 1);
    }

    const dist = Math.max(radius, 8) * 2.2;
    const endPos = centeredTarget.clone().add(normal.clone().multiplyScalar(dist));

    animRef.current = {
      startPos: camera.position.clone(),
      endPos,
      startTarget: controlsRef.current
        ? controlsRef.current.target.clone()
        : new Vector3(center.x, center.y, center.z),
      endTarget: centeredTarget,
      progress: 0,
    };
    invalidate();
  }, [focusPanelId, camera, center, invalidate, radius, sceneData]);

  useFrame((_, delta) => {
    let needsUpdate = false;

    // Focus-panel animation
    const anim = animRef.current;
    if (anim) {
      anim.progress = Math.min(1, anim.progress + delta * 2.5);
      const t = easeInOutCubic(anim.progress);

      camera.position.lerpVectors(anim.startPos, anim.endPos, t);

      if (controlsRef.current) {
        controlsRef.current.target.lerpVectors(
          anim.startTarget,
          anim.endTarget,
          t,
        );
      }

      if (anim.progress >= 1) animRef.current = null;
      needsUpdate = true;
    }

    // Keyboard pan
    const keys = keysPressed.current;
    if (keys.size > 0) {
      const speed = Math.max(radius, 8) * 0.8 * delta;
      // Pan relative to camera's local axes (right = x, up = y)
      const right = new Vector3();
      const up = new Vector3();
      camera.getWorldDirection(new Vector3()); // ensure matrix is fresh
      right.setFromMatrixColumn(camera.matrix, 0); // camera-right
      up.setFromMatrixColumn(camera.matrix, 1);    // camera-up

      const panOffset = new Vector3();
      if (keys.has("a") || keys.has("arrowleft")) panOffset.addScaledVector(right, -speed);
      if (keys.has("d") || keys.has("arrowright")) panOffset.addScaledVector(right, speed);
      if (keys.has("w") || keys.has("arrowup")) panOffset.addScaledVector(up, speed);
      if (keys.has("s") || keys.has("arrowdown")) panOffset.addScaledVector(up, -speed);

      camera.position.add(panOffset);
      if (controlsRef.current) controlsRef.current.target.add(panOffset);
      needsUpdate = true;
    }

    if (needsUpdate) {
      if (controlsRef.current) controlsRef.current.update();
      camera.updateProjectionMatrix();
      invalidate();
    }
  });

  return (
    <OrbitControls
      ref={controlsRef}
      dampingFactor={0.08}
      enableDamping
      enablePan
      enableRotate
      enableZoom
      makeDefault
      maxDistance={Math.max(radius * 8, 120)}
      minDistance={Math.max(radius * 0.5, 6)}
    />
  );
}

function SceneGrid({ radius, centerZ }: { radius: number; centerZ: number }) {
  const gridSize = Math.max(radius * 4, 200);
  const gridDivisions = Math.round(gridSize / 10);
  return (
    <gridHelper
      args={[gridSize, gridDivisions, "#93a4b1", "#d6dee6"]}
      position={[0, 0, centerZ]}
    />
  );
}

function easeInOutCubic(t: number) {
  return t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2;
}

function usePanelTexture(
  sceneNode: NonNullable<ReturnType<typeof buildPreviewSceneData>>["nodes"][number],
) {
  const [texture, setTexture] = useState<CanvasTexture | null>(null);
  const invalidate = useThree((state) => state.invalidate);

  useEffect(() => {
    let cancelled = false;

    loadPanelTextureCanvas(sceneNode.node, sceneNode.contents).then((asset) => {
      log3DDebug(`panel ${sceneNode.node.panel_id ?? "unknown"} texture asset`, {
        status: asset.status,
        hasCanvas: Boolean(asset.canvas),
        canvasSize: asset.canvas
          ? { width: asset.canvas.width, height: asset.canvas.height }
          : null,
      });

      if (cancelled || !asset.canvas) return;

      const nextTexture = new CanvasTexture(asset.canvas);
      nextTexture.colorSpace = SRGBColorSpace;
      nextTexture.minFilter = LinearFilter;
      nextTexture.magFilter = LinearFilter;
      nextTexture.wrapS = ClampToEdgeWrapping;
      nextTexture.wrapT = ClampToEdgeWrapping;
      nextTexture.generateMipmaps = false;
      nextTexture.flipY = false;
      nextTexture.needsUpdate = true;

      setTexture(nextTexture);
      log3DDebug(`panel ${sceneNode.node.panel_id ?? "unknown"} texture attached`, {
        uuid: nextTexture.uuid,
        image: {
          width: nextTexture.image.width,
          height: nextTexture.image.height,
        },
        flipY: nextTexture.flipY,
      });
      invalidate();
    });

    return () => {
      cancelled = true;
    };
  }, [invalidate, sceneNode.contents, sceneNode.node]);

  return texture;
}

function assignExtrudeMaterialGroups(geometry: BufferGeometry) {
  const normals = geometry.getAttribute("normal");
  const vertexCount = normals.count;
  const faceCount = vertexCount / 3;

  geometry.clearGroups();

  // Collect faces into cap (materialIndex 0) and side (materialIndex 1) buckets
  const capFaces: number[] = [];
  const sideFaces: number[] = [];

  for (let f = 0; f < faceCount; f++) {
    const base = f * 3;
    const nz0 = normals.getZ(base);
    const nz1 = normals.getZ(base + 1);
    const nz2 = normals.getZ(base + 2);
    const avgNz = (nz0 + nz1 + nz2) / 3;

    if (Math.abs(avgNz) > 0.5) {
      capFaces.push(f);
    } else {
      sideFaces.push(f);
    }
  }

  // Add contiguous groups for caps
  for (const f of capFaces) {
    geometry.addGroup(f * 3, 3, 0);
  }
  // Add contiguous groups for sides
  for (const f of sideFaces) {
    geometry.addGroup(f * 3, 3, 1);
  }
}

function buildOutlineGeometry(points: [number, number, number][]) {
  if (points.length < 2) return null;

  const geometry = new BufferGeometry();
  geometry.setAttribute(
    "position",
    new Float32BufferAttribute(points.flat(), 3),
  );
  return geometry;
}

function summarizeGeometry(geometry: BufferGeometry) {
  const position = geometry.getAttribute("position");
  const uv = geometry.getAttribute("uv");

  return {
    hasIndex: Boolean(geometry.getIndex()),
    vertexCount: position?.count ?? 0,
    uvCount: uv?.count ?? 0,
  };
}

function summarizeUvRange(geometry: BufferGeometry) {
  const uv = geometry.getAttribute("uv");
  if (!uv || uv.count === 0) {
    return null;
  }

  let minU = Number.POSITIVE_INFINITY;
  let minV = Number.POSITIVE_INFINITY;
  let maxU = Number.NEGATIVE_INFINITY;
  let maxV = Number.NEGATIVE_INFINITY;

  for (let index = 0; index < uv.count; index += 1) {
    const u = uv.getX(index);
    const v = uv.getY(index);
    minU = Math.min(minU, u);
    minV = Math.min(minV, v);
    maxU = Math.max(maxU, u);
    maxV = Math.max(maxV, v);
  }

  return { minU, minV, maxU, maxV };
}

function EmptyState({ label }: { label: string }) {
  return (
    <div className="flex h-[520px] items-center justify-center rounded-[1.5rem] border border-dashed border-border bg-white/40 px-6 text-center text-sm text-muted-foreground">
      {label}
    </div>
  );
}
