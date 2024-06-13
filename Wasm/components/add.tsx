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

const Loaded: React.FC<LoadedProps> = ({ module }) => {
  const array = new Uint8Array(moduleMemory.buffer);
  const offset = module.getBufferPointer();
  const data = array.slice(offset, offset + 16);

  console.log("data", data);
  return (
    <div>
      Added up: {module.add(1, 2)} Offset: {offset}
    </div>
  );
};
