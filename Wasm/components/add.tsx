"use client";

import { AddModuleExports, ModuleContext, moduleMemory } from "@/app/provider";
import React, { useContext, useEffect, useState } from "react";

interface AddProps {}

export const Add: React.FC<AddProps> = () => {
  const module = useContext(ModuleContext);

  return module ? <Loaded module={module} /> : <div>Loading...</div>;
};

interface LoadedProps {
  module: AddModuleExports;
}

function getBuffer(
  getBufferPointer: AddModuleExports["getBufferPointer"],
): Uint8Array {
  const array = new Uint8Array(moduleMemory.buffer);
  const offset = getBufferPointer();
  return array.slice(offset, offset + 16);
}

const Loaded: React.FC<LoadedProps> = ({ module }) => {
  const [val, setVal] = useState<Uint8Array>(
    getBuffer(module.getBufferPointer),
  );

  useEffect(() => {
    const interval = setInterval(() => {
      module.computeBuffer();
      setVal(getBuffer(module.getBufferPointer));
    }, 1000);

    return () => clearInterval(interval);
  }, []);

  val.entries();

  return (
    <div>
      <h1>Ayoooo</h1>
      {val.join(", ")}
    </div>
  );
};
