import { WebGL } from "@/components/perlin";

export default function Home() {
  return (
    <main className="bg-black flex min-h-screen flex-col items-center justify-between p-24">
      <WebGL />
    </main>
  );
}
