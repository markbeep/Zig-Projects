"use client";

import { AddModuleExports, moduleMemory, useModule } from "@/app/provider";
import React, { useEffect, useRef, useState } from "react";

interface WebGLProps {}

export const WebGL: React.FC<WebGLProps> = () => {
  const ref = useRef<HTMLCanvasElement>(null);
  const [gl, setGl] = useState<CanvasRenderingContext2D | undefined>();
  const module = useModule(gl);

  useEffect(() => {
    if (ref.current === null) return;
    const gl = ref.current?.getContext("2d");
    if (!gl) return;
    gl.canvas.height = 500;
    gl.canvas.width = 500;
    setGl(gl);
  }, [ref]);

  return <WebGlCanvas inputRef={ref} module={module} />;
};

let keyBuffer: Uint8Array | null = null;

interface WebGlCanvasProps {
  inputRef: React.RefObject<HTMLCanvasElement>;
  module: AddModuleExports | null;
}

const WebGlCanvas: React.FC<WebGlCanvasProps> = ({ inputRef, module }) => {
  useEffect(() => {
    if (!module) return;

    const addKey = (down: boolean) => (e: KeyboardEvent) => {
      if (keyBuffer === null) {
        const offset = module.keyboard_offset();
        keyBuffer = new Uint8Array(moduleMemory.buffer, offset, 32);
      }
      // Transfer key to wasm buffer
      for (let i = 0; i < e.key.length; i++) {
        keyBuffer[i] = e.key.charCodeAt(i);
      }
      module.register_keypress(e.key.length, down);
    };

    window.addEventListener("keydown", addKey(true));
    window.addEventListener("keyup", addKey(false));

    module.init();
    // animation loop
    function update(time: DOMHighResTimeStamp) {
      module!.update(time);
      requestAnimationFrame(update);
    }
    requestAnimationFrame(update);

    return () => {
      window.removeEventListener("keydown", addKey(true));
      window.removeEventListener("keyup", addKey(false));
    };
  }, [module]);

  return (
    <div className="flex flex-col items-center gap-2">
      <canvas className="h-[500px] w-[500px]" ref={inputRef} />
    </div>
  );
};
