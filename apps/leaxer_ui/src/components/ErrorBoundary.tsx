import { Component, type ErrorInfo, type ReactNode } from 'react';
import { AlertTriangle, RefreshCw } from 'lucide-react';
import { Button } from './ui/button';

interface ErrorBoundaryProps {
  children: ReactNode;
  fallback?: ReactNode;
  /** Name of the component for error logging */
  componentName?: string;
  /** Callback when an error is caught */
  onError?: (error: Error, errorInfo: ErrorInfo) => void;
  /** Custom reset handler */
  onReset?: () => void;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
  errorInfo: ErrorInfo | null;
}

/**
 * Error boundary component that catches JavaScript errors in child components.
 * Prevents crashes from propagating and crashing the entire UI.
 */
export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = {
      hasError: false,
      error: null,
      errorInfo: null,
    };
  }

  static getDerivedStateFromError(error: Error): Partial<ErrorBoundaryState> {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo): void {
    const { componentName, onError } = this.props;

    // Log error details for debugging
    console.error(
      `[ErrorBoundary${componentName ? `:${componentName}` : ''}] Caught error:`,
      error
    );
    console.error('Error info:', errorInfo);

    this.setState({ errorInfo });

    // Call optional error callback
    if (onError) {
      onError(error, errorInfo);
    }
  }

  handleReset = (): void => {
    const { onReset } = this.props;

    this.setState({
      hasError: false,
      error: null,
      errorInfo: null,
    });

    if (onReset) {
      onReset();
    }
  };

  render(): ReactNode {
    const { children, fallback, componentName } = this.props;
    const { hasError, error } = this.state;

    if (hasError) {
      // Use custom fallback if provided
      if (fallback) {
        return fallback;
      }

      // Default error UI
      return (
        <ErrorFallback
          componentName={componentName}
          error={error}
          onReset={this.handleReset}
        />
      );
    }

    return children;
  }
}

interface ErrorFallbackProps {
  componentName?: string;
  error: Error | null;
  onReset: () => void;
}

/**
 * Default fallback UI shown when an error occurs.
 */
function ErrorFallback({ componentName, error, onReset }: ErrorFallbackProps): ReactNode {
  return (
    <div className="flex items-center justify-center w-full h-full min-h-[200px] p-4">
      <div className="flex flex-col items-center gap-4 max-w-md text-center">
        <div className="flex items-center justify-center w-12 h-12 rounded-full bg-red-500/10">
          <AlertTriangle className="w-6 h-6 text-red-500" />
        </div>

        <div className="space-y-2">
          <h3 className="text-lg font-semibold text-[var(--color-text)]">
            {componentName ? `${componentName} crashed` : 'Something went wrong'}
          </h3>
          <p className="text-sm text-[var(--color-subtext0)]">
            An unexpected error occurred. Try refreshing this component.
          </p>
        </div>

        {error && (
          <div className="w-full p-3 rounded-md bg-[var(--color-surface0)] border border-[var(--color-surface1)]">
            <p className="text-xs font-mono text-[var(--color-red)] break-all">
              {error.message}
            </p>
          </div>
        )}

        <Button onClick={onReset} variant="outline" size="sm" className="gap-2">
          <RefreshCw className="w-4 h-4" />
          Try again
        </Button>
      </div>
    </div>
  );
}

/**
 * Specialized error boundary for the NodeGraph component.
 * Provides a full-screen recovery UI.
 */
export function NodeGraphErrorBoundary({
  children,
  onReset,
}: {
  children: ReactNode;
  onReset?: () => void;
}): ReactNode {
  return (
    <ErrorBoundary
      componentName="Node Graph"
      onReset={onReset}
      fallback={<NodeGraphErrorFallback onReset={onReset} />}
    >
      {children}
    </ErrorBoundary>
  );
}

function NodeGraphErrorFallback({
  onReset,
}: {
  onReset?: () => void;
}): ReactNode {
  const handleRefresh = () => {
    if (onReset) {
      onReset();
    }
    // Force a page reload as last resort for graph errors
    window.location.reload();
  };

  return (
    <div className="flex items-center justify-center w-full h-full bg-[var(--color-base)]">
      <div className="flex flex-col items-center gap-6 max-w-lg text-center p-8">
        <div className="flex items-center justify-center w-16 h-16 rounded-full bg-red-500/10">
          <AlertTriangle className="w-8 h-8 text-red-500" />
        </div>

        <div className="space-y-3">
          <h2 className="text-xl font-semibold text-[var(--color-text)]">
            Node Graph Crashed
          </h2>
          <p className="text-sm text-[var(--color-subtext0)]">
            The node editor encountered an unexpected error. Your workflow data may still be
            recoverable. Click the button below to reload.
          </p>
        </div>

        <div className="flex gap-3">
          <Button onClick={handleRefresh} className="gap-2">
            <RefreshCw className="w-4 h-4" />
            Reload Editor
          </Button>
        </div>

        <p className="text-xs text-[var(--color-subtext1)]">
          If this keeps happening, try clearing your browser cache or opening a new workflow.
        </p>
      </div>
    </div>
  );
}
