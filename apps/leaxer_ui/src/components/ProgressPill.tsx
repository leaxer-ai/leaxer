import { useGraphStore, type JobStatus } from '../stores/graphStore';
import { useWorkflowStore } from '../stores/workflowStore';
import { useQueueStore } from '../stores/queueStore';
import { cn } from '@/lib/utils';
import { useEffect, useState, useRef } from 'react';
import './ProgressPill.css';

type AnimationPhase = 'hidden' | 'entering-slide' | 'entering-grow' | 'running' | 'exiting-complete' | 'exiting-bounce';

export function ProgressPill() {
  const isExecuting = useGraphStore((s) => s.isExecuting);
  const graphProgress = useGraphStore((s) => s.graphProgress);
  const nodeProgress = useGraphStore((s) => s.nodeProgress);
  const currentNode = useGraphStore((s) => s.currentNode);
  const lastJobStatus = useGraphStore((s) => s.lastJobStatus);
  const nodes = useWorkflowStore((s) => {
    const tabId = s.activeTabId || s.tabs[0]?.id;
    const tab = s.tabs.find((t) => t.id === tabId);
    return tab?.nodes ?? [];
  });
  const pendingCount = useQueueStore((s) => s.pendingCount());

  const [phase, setPhase] = useState<AnimationPhase>('hidden');
  const [displayStatus, setDisplayStatus] = useState<JobStatus>(null);
  const previousExecuting = useRef(isExecuting);
  const previousPendingCount = useRef(pendingCount);

  // Orchestrate entrance and exit animations
  useEffect(() => {
    const isActive = isExecuting || pendingCount > 0;
    const wasActive = previousExecuting.current || previousPendingCount.current > 0;

    // Starting execution - entrance sequence (only if pill is hidden)
    if (isActive && !wasActive && phase === 'hidden') {
      setPhase('entering-slide');
      setTimeout(() => setPhase('entering-grow'), 400);
      setTimeout(() => setPhase('running'), 800); // Pill expands, then content fades in
    }
    // Stopping execution - exit sequence (only when both execution stops AND no pending jobs)
    else if (!isActive && wasActive) {
      // Capture the status at the moment execution stops
      setDisplayStatus(lastJobStatus);

      // Exit sequence
      setPhase('exiting-complete');
      setTimeout(() => setPhase('exiting-bounce'), 3000); // Wait 3 seconds
      setTimeout(() => setPhase('hidden'), 3800);
    }

    previousExecuting.current = isExecuting;
    previousPendingCount.current = pendingCount;
  }, [isExecuting, pendingCount, lastJobStatus, phase]);

  // Get current node info
  const currentNodeData = currentNode ? nodes.find(n => n.id === currentNode) : null;
  const nodeType = currentNodeData?.type;
  const customTitle = currentNodeData?.data?._title as string | undefined;

  // Use custom title if set, otherwise show node type
  const getNodeDisplayName = () => {
    if (customTitle) return customTitle;
    return nodeType || 'Processing';
  };
  const currentNodeName = getNodeDisplayName();

  const currentNodeProgress = currentNode ? nodeProgress[currentNode] : null;

  const hasValidSteps = currentNodeProgress?.totalSteps != null
    && currentNodeProgress.totalSteps > 0
    && currentNodeProgress?.currentStep != null
    && currentNodeProgress.currentStep >= 1;

  const isLoading = currentNodeProgress?.phase === 'loading';

  // Calculate overall percentage
  const stepPercentage = hasValidSteps
    ? Math.round((currentNodeProgress!.currentStep! / currentNodeProgress!.totalSteps!) * 100)
    : 0;

  const graphPercentage = graphProgress?.percentage ?? 0;
  const displayPercentage = hasValidSteps ? stepPercentage : graphPercentage;

  // Build status message
  const getStatusMessage = () => {
    if (!graphProgress) return 'Initializing...';

    if (hasValidSteps) {
      if (isLoading) {
        return 'Loading model';
      }
      return `Step ${currentNodeProgress!.currentStep}/${currentNodeProgress!.totalSteps}`;
    }

    return `Node ${graphProgress.currentIndex}/${graphProgress.totalNodes}`;
  };

  const isVisible = phase !== 'hidden';
  const showContent = phase === 'running'; // Only show during running, hide during entrance and exit
  const showCompleted = phase === 'exiting-complete' || phase === 'exiting-bounce';

  // Determine completion message based on job status
  const getCompletionMessage = () => {
    switch (displayStatus) {
      case 'completed':
        return 'Job completed';
      case 'error':
        return 'Job failed';
      case 'stopped':
        return 'Stopped';
      default:
        return 'Done';
    }
  };
  const completionMessage = getCompletionMessage();

  return (
    <div
      className={cn(
        'fixed bottom-4 left-1/2 -translate-x-1/2 z-50',
        phase === 'entering-slide' && 'pill-entering-slide',
        phase === 'entering-grow' && 'pill-entering-grow',
        phase === 'running' && 'pill-running',
        phase === 'exiting-complete' && 'pill-exiting-complete',
        phase === 'exiting-bounce' && 'pill-exiting-bounce',
        !isVisible && 'opacity-0 pointer-events-none'
      )}
    >
      {/* Main container */}
      <div className="relative">
        {/* Siri-like ambient glow - pulsing outer glow */}
        <div
          className="absolute -inset-20 rounded-full siri-ambient"
          style={{
            filter: 'blur(40px)',
          }}
        />

        {/* Glass pill container */}
        <div
          className="relative flex items-center gap-4 px-5 h-[44px] rounded-full backdrop-blur-xl overflow-hidden"
          style={{
            background: 'rgba(255, 255, 255, 0.08)',
            boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
            transition: 'width 0.2s cubic-bezier(0.34, 1.56, 0.64, 1)',
            width: (phase === 'entering-slide' || phase === 'entering-grow') ? '60px' : 'auto',
            minWidth: (phase === 'entering-slide' || phase === 'entering-grow') ? '60px' : undefined,
          }}
        >
          {/* Animated orb indicator - Siri-style */}
          <div className="relative w-4 h-4 flex-shrink-0">
            {/* Pulsing outer glow */}
            <div
              className="absolute -inset-1.5 rounded-full siri-glow"
              style={{ filter: 'blur(6px)' }}
            />
            {/* Orb core - Siri gradient */}
            <div className="absolute inset-0 rounded-full siri-orb" />
            {/* Orb highlight */}
            <div
              className="absolute inset-0 rounded-full"
              style={{
                background: 'radial-gradient(circle at 30% 30%, rgba(255,255,255,0.5) 0%, transparent 40%)',
              }}
            />
          </div>

          {/* Completion message - shows during exit */}
          {showCompleted && (
            <div
              className={cn(
                "flex items-center gap-2.5 transition-opacity duration-300",
                phase === 'exiting-complete' ? "opacity-100" : "opacity-0"
              )}
            >
              <span
                className="font-medium text-[13px] px-2"
                style={{ color: 'var(--color-text)' }}
              >
                {completionMessage}
              </span>
            </div>
          )}

          {/* Content - fades in after grow animation, hidden during exit */}
          {!showCompleted && (
            <div
              className={cn(
                "flex items-center gap-2.5 transition-opacity duration-300",
                showContent ? "opacity-100" : "opacity-0"
              )}
            >
              {/* Node name */}
              <span
                className="font-medium text-[13px] truncate max-w-[120px]"
                style={{ color: 'var(--color-text)' }}
                title={currentNodeName}
              >
                {currentNodeName}
              </span>

              {/* Separator */}
              <span style={{ color: 'var(--color-text-muted)' }}>·</span>

              {/* Status */}
              <span
                className="text-[13px]"
                style={{ color: 'var(--color-text-secondary)' }}
              >
                {getStatusMessage()}
              </span>
            </div>
          )}

          {/* Progress bar - only show when running */}
          {!showCompleted && (
            <>
              <div
                className={cn(
                  "relative w-20 h-1.5 rounded-full overflow-hidden flex-shrink-0 transition-opacity duration-300",
                  showContent ? "opacity-100" : "opacity-0"
                )}
                style={{ background: 'color-mix(in srgb, var(--color-text) 10%, transparent)' }}
              >
                {/* Fill - Siri animated bar */}
                <div
                  className={cn(
                    "absolute inset-y-0 left-0 rounded-full siri-bar",
                    "transition-[width] duration-500 ease-out"
                  )}
                  style={{ width: `${displayPercentage}%` }}
                />
                {/* Glass shine */}
                <div
                  className="absolute inset-0 rounded-full"
                  style={{
                    background: 'linear-gradient(180deg, rgba(255,255,255,0.2) 0%, transparent 50%)',
                  }}
                />
              </div>

              {/* Percentage */}
              <span
                className={cn(
                  "font-medium text-[13px] tabular-nums min-w-[32px] text-right flex-shrink-0 transition-opacity duration-300",
                  showContent ? "opacity-100" : "opacity-0"
                )}
                style={{ color: 'var(--color-text)' }}
              >
                {displayPercentage}%
              </span>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
