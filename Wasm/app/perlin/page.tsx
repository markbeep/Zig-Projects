import { ModuleProvider } from "@/app/provider";
import { Perlin } from "@/components/perlin";

export default function Home() {
  return (
    <ModuleProvider>
      <main className="flex min-h-screen flex-col items-center justify-between p-24">
        <Perlin />
      </main>
    </ModuleProvider>
  );
}
