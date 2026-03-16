import { OrbitControls } from "@react-three/drei";
import { Canvas, useThree } from "@react-three/fiber";
import { useEffect, useMemo, useRef, useState } from "react";
import {
  ACESFilmicToneMapping,
  BufferGeometry,
  ClampToEdgeWrapping,
  CanvasTexture,
  DoubleSide,
  Float32BufferAttribute,
  LinearFilter,
  Line as ThreeLine,
  LineBasicMaterial,
  MeshBasicMaterial,
  PerspectiveCamera,
  ShapeGeometry,
  SRGBColorSpace,
} from "three";
import { pathToShape } from "@/lib/geometry";
import { loadPanelTextureCanvas } from "@/lib/panel-texture";
import {
  applySurfaceFrameUv,
  buildPreviewSceneData,
  fallbackSurfaceFrame,
} from "@/lib/preview-3d";
import type { GeneratedPackage } from "@/types/api";

const DEBUG_3D_RENDER = true;

export function Preview3DCanvas({
  result,
}: {
  result: GeneratedPackage["preview_3d"] | null;
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
        <gridHelper
          args={[600, 60, "#93a4b1", "#d6dee6"]}
          position={[0, 0, -24]}
        />
        <CameraRig center={sceneData.center} radius={sceneData.radius} />
        <group
          position={[
            -sceneData.center.x,
            -sceneData.center.y,
            -sceneData.center.z,
          ]}
        >
          {sceneData.nodes.map((sceneNode) => (
            <PanelNode key={sceneNode.index} sceneNode={sceneNode} />
          ))}
        </group>
      </Canvas>
    </div>
  );
}

function PanelNode({
  sceneNode,
}: {
  sceneNode: NonNullable<ReturnType<typeof buildPreviewSceneData>>["nodes"][number];
}) {
  const frame = useMemo(() => {
    if (sceneNode.node.surface_frame) return sceneNode.node.surface_frame;
    return sceneNode.node.boundary
      ? fallbackSurfaceFrame(sceneNode.node.boundary)
      : null;
  }, [sceneNode.node.boundary, sceneNode.node.surface_frame]);

  const geometry = useMemo(() => {
    if (!sceneNode.node.boundary || !frame) return null;

    const indexedGeometry = new ShapeGeometry(
      pathToShape(sceneNode.node.boundary),
    );
    const nextGeometry = indexedGeometry.toNonIndexed();
    indexedGeometry.dispose();

    applySurfaceFrameUv(nextGeometry, frame);
    nextGeometry.computeVertexNormals();
    return nextGeometry;
  }, [frame, sceneNode.node.boundary]);

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

  useEffect(() => {
    if (!DEBUG_3D_RENDER || !geometry || !frame) return;

    console.groupCollapsed(
      `[3DRender] panel ${sceneNode.node.panel_id ?? "unknown"} mesh`,
    );
    console.log("node", sceneNode.node);
    console.log("worldMatrix", sceneNode.worldMatrix.elements);
    console.log("frame", frame);
    console.log("geometry", summarizeGeometry(geometry));
    console.log("uvRange", summarizeUvRange(geometry));
    console.log("contents", sceneNode.contents);
    console.log("hasTexture", Boolean(texture));
    if (texture?.image) {
      console.log("textureImage", {
        width: texture.image.width,
        height: texture.image.height,
      });
    }
    console.groupEnd();
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
        renderOrder={1}
      >
        <meshBasicMaterial
          key={`panel-material-${sceneNode.index}-${texture?.uuid ?? "empty"}`}
          color="#ffffff"
          map={texture ?? null}
          needsUpdate
          side={DoubleSide}
          toneMapped={false}
        />
      </mesh>
      {outline ? <primitive dispose={null} object={outline} /> : null}
    </>
  );
}

function CameraRig({
  center,
  radius,
}: {
  center: { x: number; y: number; z: number };
  radius: number;
}) {
  const controlsRef = useRef<any>(null);
  const camera = useThree((state) => state.camera as PerspectiveCamera);
  const invalidate = useThree((state) => state.invalidate);

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

function usePanelTexture(
  sceneNode: NonNullable<ReturnType<typeof buildPreviewSceneData>>["nodes"][number],
) {
  const [texture, setTexture] = useState<CanvasTexture | null>(null);
  const invalidate = useThree((state) => state.invalidate);

  useEffect(() => {
    let cancelled = false;

    loadPanelTextureCanvas(sceneNode.node, sceneNode.contents).then((asset) => {
      if (DEBUG_3D_RENDER) {
        console.log(`[3DRender] panel ${sceneNode.node.panel_id ?? "unknown"} texture asset`, {
          status: asset.status,
          hasCanvas: Boolean(asset.canvas),
          canvasSize: asset.canvas
            ? { width: asset.canvas.width, height: asset.canvas.height }
            : null,
        });
      }

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
      if (DEBUG_3D_RENDER) {
        console.log(
          `[3DRender] panel ${sceneNode.node.panel_id ?? "unknown"} texture attached`,
          {
            uuid: nextTexture.uuid,
            image: {
              width: nextTexture.image.width,
              height: nextTexture.image.height,
            },
            flipY: nextTexture.flipY,
          },
        );
      }
      invalidate();
    });

    return () => {
      cancelled = true;
    };
  }, [invalidate, sceneNode.contents, sceneNode.node]);

  return texture;
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
