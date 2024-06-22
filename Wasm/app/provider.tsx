"use client";

import { useEffect, useState } from "react";

export interface AddModuleExports {
  init(): void;
  update(time: DOMHighResTimeStamp): void;
  keyboard(key: number, down: boolean): void;
}

export const moduleMemory = new WebAssembly.Memory({
  initial: 18,
  maximum: 18,
});

const width = 500;
const height = 500;

let buffer: Uint8ClampedArray | null = null;

function getBuffer(offset: number) {
  const buffer = new Uint8ClampedArray(
    moduleMemory.buffer,
    offset,
    width * height * 4,
  );
  return buffer;
}

export const useModule = (gl: CanvasRenderingContext2D | undefined) => {
  const [module, setModule] = useState<AddModuleExports | null>(null);

  useEffect(() => {
    if (!gl) return;

    WebAssembly.instantiateStreaming(fetch("/add.wasm"), {
      env: {
        memory: moduleMemory,

        // Functions
        drawBuffer: (offset: number) => {
          if (!buffer) {
            buffer = getBuffer(offset);
          }
          const imageData = new ImageData(buffer, width, height);
          gl.putImageData(imageData, 0, 0);
        },
      },
    }).then(a => setModule(a.instance.exports as unknown as AddModuleExports));
  }, [gl]);

  return module;
};
