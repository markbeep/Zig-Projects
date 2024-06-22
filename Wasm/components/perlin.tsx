"use client";

import { AddModuleExports, useModule } from "@/app/provider";
import React, { useEffect, useRef, useState } from "react";

interface WebGLProps {}

export const WebGL: React.FC<WebGLProps> = () => {
  const ref = useRef<HTMLCanvasElement>(null);
  const [gl, setGl] = useState<WebGLRenderingContext | undefined>();
  const module = useModule(gl);

  console.log("module", module, gl);

  useEffect(() => {
    if (ref.current === null) return;
    const gl = ref.current?.getContext("webgl");
    if (!gl) return;
    setGl(gl);
  }, [ref]);

  return <WebGlCanvas inputRef={ref} module={module} />;
};

interface WebGlCanvasProps {
  inputRef: React.RefObject<HTMLCanvasElement>;
  module: AddModuleExports | null;
}

const WebGlCanvas: React.FC<WebGlCanvasProps> = ({ inputRef, module }) => {
  useEffect(() => {
    if (!module) return;

    module.init();

    // animation loop
    function update(time: DOMHighResTimeStamp) {
      module!.update(time);
      requestAnimationFrame(update);
    }
    requestAnimationFrame(update);
  }, [module]);

  return <canvas className="h-[500px] w-[500px]" ref={inputRef} />;
};
