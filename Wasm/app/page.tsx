import { Add } from "@/components/add";
import { ModuleProvider } from "./provider";

export default function Home() {
  return (
    <ModuleProvider>
      <main className="flex min-h-screen flex-col items-center justify-between p-24">
        <Add />
      </main>
    </ModuleProvider>
  );
}
