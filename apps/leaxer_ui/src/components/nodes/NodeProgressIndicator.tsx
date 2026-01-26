interface NodeProgressIndicatorProps {
  percentage: number;
  currentStep: number | null;
  totalSteps: number | null;
}

export function NodeProgressIndicator({
  percentage,
  currentStep,
  totalSteps,
}: NodeProgressIndicatorProps) {
  // Only show step badge when we have valid step progress (step >= 1)
  const hasValidSteps = totalSteps != null && totalSteps > 0 && currentStep != null && currentStep >= 1;

  return (
    <div className="absolute -bottom-1 left-0 right-0">
      {/* Progress bar */}
      <div className="h-1 bg-surface-1 rounded-full overflow-hidden mx-1">
        <div
          className="h-full bg-peach rounded-full transition-all duration-150 ease-out"
          style={{ width: `${percentage}%` }}
        />
      </div>

      {/* Step count badge - only show when we have valid step progress */}
      {hasValidSteps && (
        <div className="absolute -top-5 right-2 bg-peach/90 text-[10px] text-crust font-medium px-1.5 py-0.5 rounded-md shadow-lg">
          {currentStep}/{totalSteps}
        </div>
      )}
    </div>
  );
}
