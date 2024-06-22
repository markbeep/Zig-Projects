"use client";

import { useEffect, useMemo, useState } from "react";

export interface AddModuleExports {
  getBufferPointer(): number;
  computePerlin(): void;
  setSeed(seed: number): void;
  init(): void;
  update(time: DOMHighResTimeStamp): void;
}

export const moduleMemory = new WebAssembly.Memory({
  initial: 14,
  maximum: 14,
});

export const useModule = (gl: WebGLRenderingContext | undefined) => {
  const [module, setModule] = useState<AddModuleExports | null>(null);

  useEffect(() => {
    if (!gl) return;

    WebAssembly.instantiateStreaming(fetch("/add.wasm"), {
      env: {
        memory: moduleMemory,
        print: (num: number) => console.log(`Number: ${num}`),

        // WebGL
        glClearColor: (r: number, g: number, b: number, a: number) =>
          gl.clearColor(r, g, b, a),
        glClear: () => gl.clear(gl.COLOR_BUFFER_BIT),
      },
    }).then(a => setModule(a.instance.exports as unknown as AddModuleExports));
  }, [gl]);

  return module;
};
