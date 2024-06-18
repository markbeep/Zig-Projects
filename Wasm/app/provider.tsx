"use client";

import React, { useEffect, useState } from "react";

export interface AddModuleExports {
  add(a: number, b: number): number;
  getBufferPointer(): number;
  computeBuffer(): void;
}

export const ModuleContext = React.createContext<AddModuleExports | null>(null);

export const moduleMemory = new WebAssembly.Memory({
  initial: 2,
  maximum: 2,
});

interface ModuleProviderProps {}

export const ModuleProvider: React.FC<
  React.PropsWithChildren<ModuleProviderProps>
> = ({ children }) => {
  const [module, setModule] = useState<AddModuleExports | null>(null);

  useEffect(() => {
    WebAssembly.instantiateStreaming(fetch("/add.wasm"), {
      env: {
        memory: moduleMemory,
        print: (num: number) => console.log(`Number: ${num}`),
      },
    }).then(a => setModule(a.instance.exports as unknown as AddModuleExports));
  }, []);

  return (
    <ModuleContext.Provider value={module}>{children}</ModuleContext.Provider>
  );
};
