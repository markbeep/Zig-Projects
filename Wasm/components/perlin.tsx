"use client";

import { AddModuleExports, ModuleContext, moduleMemory } from "@/app/provider";
import React, { useContext, useEffect, useRef } from "react";

const height = 500,
  width = 500;

interface PerlinProps {}

export const Perlin: React.FC<PerlinProps> = ({}) => {
  const module = useContext(ModuleContext);

  return module ? <PerlinCanvas module={module} /> : null;
};

function getBuffer(offset: number): Uint8Array {
  const array = new Uint8Array(moduleMemory.buffer);
  return array.slice(offset, offset + 500 * 500 * 3); // RGB
}

interface PerlinCanvasProps {
  module: AddModuleExports;
}

const PerlinCanvas: React.FC<PerlinCanvasProps> = ({ module }) => {
  const ref = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    if (ref.current === null) return;
    const canvas = ref.current?.getContext("2d");
    if (!canvas) return;
    canvas.fillStyle = "white";
    canvas.fillRect(0, 0, width, height);
    module.setSeed(Date.now());
    module.computePerlin();

    const arr = getBuffer(module.getBufferPointer());
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const r = arr[(y * width + x) * 3];
        const g = arr[(y * width + x) * 3 + 1];
        const b = arr[(y * width + x) * 3 + 2];
        const rgb = (r << 16) + (g << 8) + b;
        canvas.fillStyle = `#${rgb.toString(16)}`;
        canvas.fillRect(x, y, 1, 1);
      }
    }
  }, [ref]);

  return <canvas className="h-[500px] w-[500px]" ref={ref} />;
};
