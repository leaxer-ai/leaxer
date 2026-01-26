import { memo } from 'react';
import { cn } from '@/lib/utils';
import { useViewStore, type ViewType } from '@/stores/viewStore';

interface ViewTabProps {
  label: string;
  isActive: boolean;
  onClick: () => void;
}

const ViewTab = memo(({ label, isActive, onClick }: ViewTabProps) => (
  <button
    onClick={onClick}
    className={cn(
      'px-3 py-1.5 rounded-full text-xs font-medium transition-colors duration-75 whitespace-nowrap',
      isActive
        ? 'bg-[var(--color-accent)] text-[var(--color-crust)]'
        : 'text-[var(--color-text-secondary)] hover:text-[var(--color-text)] hover:bg-surface-1/50'
    )}
  >
    {label}
  </button>
));

ViewTab.displayName = 'ViewTab';

interface ViewTabsProps {
  isExpanded?: boolean;
}

export const ViewTabs = memo(({ isExpanded = false }: ViewTabsProps) => {
  const currentView = useViewStore((s) => s.currentView);
  const setCurrentView = useViewStore((s) => s.setCurrentView);

  const tabs: { view: ViewType; label: string }[] = [
    { view: 'chat', label: 'Chat' },
    { view: 'node', label: 'Node' },
  ];

  return (
    <div
      className="flex items-center rounded-full h-[44px] min-w-[44px] pl-3.5 backdrop-blur-xl"
      style={{
        background: 'rgba(255, 255, 255, 0.08)',
        boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
      }}
    >
      {/* Logo */}
      <div className="flex items-center justify-center flex-shrink-0">
        <div
          className="h-4 w-4"
          style={{
            backgroundColor: 'var(--color-text-secondary)',
            maskImage: 'url(/leaxer-icon.svg)',
            WebkitMaskImage: 'url(/leaxer-icon.svg)',
            maskRepeat: 'no-repeat',
            WebkitMaskRepeat: 'no-repeat',
            maskSize: 'contain',
            WebkitMaskSize: 'contain',
            maskPosition: 'center',
            WebkitMaskPosition: 'center',
          }}
          aria-label="Leaxer"
        />
      </div>

      {/* Tabs - hidden until hover */}
      <div
        className={cn(
          'flex items-center gap-0.5 overflow-hidden transition-all duration-200 ease-out',
          isExpanded ? 'max-w-[200px] opacity-100 ml-2 pr-2' : 'max-w-0 opacity-0'
        )}
      >
        {tabs.map((tab) => (
          <ViewTab
            key={tab.view}
            label={tab.label}
            isActive={currentView === tab.view}
            onClick={() => setCurrentView(tab.view)}
          />
        ))}
      </div>
    </div>
  );
});

ViewTabs.displayName = 'ViewTabs';
