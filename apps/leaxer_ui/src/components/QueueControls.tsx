import { Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

interface QueueControlsProps {
  connected: boolean;
  isExecuting: boolean;
  error: string | null;
  onQueuePrompt: () => void;
  onReset: () => void;
}

export function QueueControls({
  connected,
  isExecuting,
  error,
  onQueuePrompt,
  onReset,
}: QueueControlsProps) {
  return (
    <div className="absolute bottom-6 left-1/2 -translate-x-1/2 flex flex-col items-center gap-2">
      {error && (
        <div className="bg-red-900/80 backdrop-blur border border-red-700 rounded-lg px-4 py-2 text-red-200 text-sm max-w-md text-center">
          {error}
        </div>
      )}
      <div className="bg-zinc-900/80 backdrop-blur border border-zinc-700 rounded-lg px-4 py-3 flex items-center gap-4">
        <div
          className={cn(
            "w-2 h-2 rounded-full",
            connected ? "bg-green-500" : "bg-red-500"
          )}
        />
        <Button
          onClick={onQueuePrompt}
          disabled={!connected || isExecuting}
        >
          {isExecuting && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
          Queue Prompt
        </Button>
        <Button variant="ghost" onClick={onReset}>
          Reset
        </Button>
      </div>
    </div>
  );
}
