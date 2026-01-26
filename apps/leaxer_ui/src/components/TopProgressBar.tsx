import { useGraphStore } from '../stores/graphStore';
import { useQueueStore } from '../stores/queueStore';

export function TopProgressBar() {
  const graphProgress = useGraphStore((s) => s.graphProgress);
  const nodeProgress = useGraphStore((s) => s.nodeProgress);
  const currentNode = useGraphStore((s) => s.currentNode);
  const isExecuting = useGraphStore((s) => s.isExecuting);
  const pendingCount = useQueueStore((s) => s.pendingCount());
  const isActive = isExecuting || pendingCount > 0;

  const currentNodeProgress = currentNode ? nodeProgress[currentNode] : null;
  const hasStepProgress = currentNodeProgress?.totalSteps != null;

  // Calculate overall percentage (blend graph and step progress)
  const overallPercentage = hasStepProgress && currentNodeProgress
    ? (graphProgress?.percentage ?? 0) * 0.3 + currentNodeProgress.percentage * 0.7
    : graphProgress?.percentage ?? 0;

  return (
    <div
      className={`fixed top-0 left-0 right-0 z-50 transition-all duration-300 ease-out overflow-hidden ${
        isActive ? 'h-12' : 'h-0'
      }`}
    >
      <div className="h-full bg-zinc-900/95 backdrop-blur-md border-b border-zinc-700">
        {/* Content row */}
        <div className="h-9 px-4 flex items-center justify-between text-xs">
          {/* Left: Status */}
          <div className="flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-amber-500 animate-pulse" />
            <span className="text-zinc-100 font-medium">Generating</span>
          </div>

          {/* Center: Node progress */}
          <div className="flex items-center gap-6 text-zinc-400">
            {graphProgress && (
              <span className="tabular-nums">
                Node <span className="text-zinc-100">{graphProgress.currentIndex}</span>
                /{graphProgress.totalNodes}
              </span>
            )}
            {hasStepProgress && currentNodeProgress && (
              <span className="tabular-nums">
                Step <span className="text-amber-400">{currentNodeProgress.currentStep || 0}</span>
                /{currentNodeProgress.totalSteps}
              </span>
            )}
          </div>

          {/* Right: Percentage */}
          <div className="tabular-nums text-zinc-100 font-medium">
            {Math.round(overallPercentage)}%
          </div>
        </div>

        {/* Progress bar */}
        <div className="h-1 bg-zinc-800">
          <div
            className="h-full bg-gradient-to-r from-blue-500 via-blue-400 to-amber-400 transition-all duration-150 ease-out"
            style={{ width: `${Math.max(overallPercentage, 1)}%` }}
          />
        </div>
      </div>
    </div>
  );
}
