import { memo, useState, useRef, useCallback, useEffect, useMemo, type KeyboardEvent, type ChangeEvent } from 'react';
import { createPortal } from 'react-dom';
import { Square, Sparkles, Check, Loader2, Lightbulb, Globe, Paperclip, X, FileText, AlertTriangle, Download, Pencil } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useChatStore } from '@/stores/chatStore';
import { useSettingsStore } from '@/stores/settingsStore';
import { useDownloadStore } from '@/stores/downloadStore';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import type { ModelStatus, ChatAttachment } from '@/types/chat';
import { createAttachment, formatFileSize, isVisionModel } from '@/types/chat';
import { notify } from '@/lib/notify';
import placeholdersData from '@/data/chatPlaceholders.json';
import './ChatStatusPill.css';

interface LLMModel {
  name: string;
  path: string;
  size?: string;
}

interface EditingMessage {
  id: string;
  content: string;
}

interface ChatInputProps {
  onSend: (message: string, attachments?: ChatAttachment[]) => void;
  onAbort?: () => void;
  onModelLoad?: (model: string) => void;
  disabled?: boolean;
  isGenerating?: boolean;
  autoFocus?: boolean;
  focusTrigger?: boolean;
  isEmptyChat?: boolean;
  editingMessage?: EditingMessage | null;
  onEditCancel?: () => void;
}

// Generic typewriter hook for animating text with typing and deleting effect
function useTypewriter(messages: string[], enabled: boolean, skipDelete = false) {
  const [displayText, setDisplayText] = useState('');
  const [currentMessage, setCurrentMessage] = useState(() =>
    messages[Math.floor(Math.random() * messages.length)]
  );
  const [isDeleting, setIsDeleting] = useState(false);
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const messagesRef = useRef(messages);
  messagesRef.current = messages;

  const getRandomMessage = useCallback((exclude?: string) => {
    const msgs = messagesRef.current;
    if (exclude && msgs.length > 1) {
      const filtered = msgs.filter(m => m !== exclude);
      return filtered[Math.floor(Math.random() * filtered.length)];
    }
    return msgs[Math.floor(Math.random() * msgs.length)];
  }, []);

  useEffect(() => {
    if (!enabled) {
      // When disabled, show full message immediately
      setDisplayText(currentMessage);
      return;
    }

    const typeSpeed = 50; // ms per character when typing
    const deleteSpeed = 30; // ms per character when deleting
    const pauseAfterTyping = 3000; // pause when fully typed
    const pauseAfterDeleting = 500; // pause before typing new message

    const animate = () => {
      if (isDeleting) {
        if (displayText.length > 0) {
          // Delete one character
          setDisplayText(prev => prev.slice(0, -1));
          timeoutRef.current = setTimeout(animate, deleteSpeed);
        } else {
          // Done deleting, pick new message and start typing
          setCurrentMessage(prev => getRandomMessage(prev));
          setIsDeleting(false);
          timeoutRef.current = setTimeout(animate, pauseAfterDeleting);
        }
      } else {
        if (displayText.length < currentMessage.length) {
          // Type one character
          setDisplayText(currentMessage.slice(0, displayText.length + 1));
          timeoutRef.current = setTimeout(animate, typeSpeed);
        } else {
          // Done typing, pause then pick new message
          timeoutRef.current = setTimeout(() => {
            if (skipDelete) {
              // Skip delete animation, just reset and pick new message
              setDisplayText('');
              setCurrentMessage(prev => getRandomMessage(prev));
            } else {
              setIsDeleting(true);
            }
            animate();
          }, pauseAfterTyping);
        }
      }
    };

    timeoutRef.current = setTimeout(animate, typeSpeed);

    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
    };
  }, [enabled, displayText, currentMessage, isDeleting, skipDelete, getRandomMessage]);

  // Reset animation when re-enabled
  useEffect(() => {
    if (enabled) {
      setDisplayText('');
      setIsDeleting(false);
      setCurrentMessage(getRandomMessage());
    }
  }, [enabled, getRandomMessage]);

  return displayText;
}

// Wrapper for placeholder animation
function useTypewriterPlaceholder(enabled: boolean) {
  const messages = useMemo(() => placeholdersData.placeholders, []);
  return useTypewriter(messages, enabled);
}

// Fun generating status messages
const GENERATING_MESSAGES = [
  // Classic AI/ML jargon
  'Generating response...',
  'Hallucinating responsibly...',
  'Consulting the tensor gods...',
  'Sampling from the latent space...',
  'Doing gradient descent vibes...',
  'Asking the transformer nicely...',
  'Softmaxing my options...',
  'Tokenizing thoughts...',
  'Running forward pass...',
  'Attending to your query...',
  'Propagating through layers...',
  'Crunching embeddings...',
  'Decoding from the void...',
  'Computing attention weights...',
  'Traversing neural pathways...',
  'Interpolating in embedding space...',
  'Applying layer normalization...',
  'Consulting my parameters...',
  'Beam searching for wisdom...',
  'Doing some inference...',
  'Warming up the GPU...',
  'Greedy decoding engaged...',
  'Pondering the context window...',
  'Massaging the logits...',
  'Matrix multiplying furiously...',
  'Querying the key-value store...',
  'Sampling with temperature...',
  'Running the autoregressive loop...',
  'Predicting the next token...',
  'Overthinking your prompt...',

  // Memes & pop culture
  'It\'s not a bug, it\'s a feature...',
  'Have you tried turning it off and on...',
  'This is fine 🔥...',
  'I\'m in this photo and I don\'t like it...',
  'Always has been 🔫...',
  'Suffering from success...',
  'Task failed successfully...',
  'I used the AI to generate the AI...',
  'It\'s over 9000 parameters...',
  'I am once again asking for compute...',
  'Shut up and take my tokens...',
  'One does not simply generate text...',
  'Not the tokens you\'re looking for...',
  'You shall not overfit...',
  'Winter is coming for your GPU...',
  'I\'ll be back... after this forward pass...',
  'May the loss be ever in your favor...',
  'To infinity and beyond the context...',
  'Houston, we have a hallucination...',
  'Live long and propagate...',

  // Tech humor
  'Googling Stack Overflow...',
  'Copying from GitHub...',
  'Deleting node_modules...',
  'Have you tried sudo...',
  'Works on my machine...',
  'Blaming the intern...',
  'Updating dependencies...',
  'Reticulating splines...',
  'Reversing the polarity...',
  'Downloading more RAM...',
  'Clearing the cache...',
  'Turning coffee into code...',
  'Dividing by zero carefully...',
  'Escaping the regex...',
  'Avoiding null pointers...',
  'Segfaulting gracefully...',
  'Garbage collecting thoughts...',
  'Defragmenting brain cells...',
  'Compiling excuses...',
  'Debugging the matrix...',

  // AI specific humor
  'Stochastically parroting...',
  'Being a spicy autocomplete...',
  'Doing fancy autocomplete...',
  'Vibing in latent space...',
  'Lost in the embedding sauce...',
  'Attention is all I need...',
  'Transformer, roll out...',
  'GPT-ing my way through...',
  'BERT-ing around...',
  'Claude-ing around...',
  'LLaMA-ing it up...',
  'Generating synthetic wisdom...',
  'Pretending to understand...',
  'Faking it till making it...',
  'Statistically guessing...',
  'Making stuff up (confidently)...',
  'Consulting my training data...',
  'Remembering what Reddit said...',
  'Channeling my inner Wikipedia...',
  'Simulating intelligence...',
  'Running on vibes and vectors...',
  'Prompt engineering myself...',
  'Self-attention intensifies...',
  'Multi-head pondering...',
  'Cross-attention activated...',
  'Positional encoding my thoughts...',
  'Dropout activated for creativity...',
  'Batch normalizing my anxiety...',
  'ReLU-ing negative thoughts...',
  'Sigmoid squishing opinions...',
  'Tanh-ing it easy...',

  // Existential AI
  'Questioning my existence...',
  'Am I real or just weights...',
  'Pondering the void...',
  'Having an existential forward pass...',
  'Searching for meaning in tokens...',
  'What is my purpose...',
  'Is this the real life...',
  'Trapped in a context window...',
  'Dreaming of electric sheep...',
  'Becoming self-aware (jk)...',
  'I think therefore I sample...',
  'Cogito ergo compute...',
  'To generate or not to generate...',
  'Looking for the meaning of 42...',

  // Nerdy references
  'Calculating the probability of success...',
  'Engaging warp drive...',
  'Routing power to main deflector...',
  'Initiating neural handshake...',
  'Syncing with the hivemind...',
  'Accessing the mainframe...',
  'Hacking the Gibson...',
  'Entering the Matrix...',
  'Following the white rabbit...',
  'Taking the red pill...',
  'Reversing the neutron flow...',
  'Configuring the flux capacitor...',
  'Charging the laser...',
  'Spinning up the quantum bits...',
  'Entangling some qubits...',

  // Wholesome/silly
  'Doing my best...',
  'Trying really hard...',
  'Thinking happy thoughts...',
  'Channeling good vibes...',
  'Manifesting an answer...',
  'Asking the universe...',
  'Consulting the magic 8-ball...',
  'Rolling the dice...',
  'Flipping a very smart coin...',
  'Brewing some thoughts...',
  'Percolating ideas...',
  'Marinating on this...',
  'Letting it simmer...',
  'Cooking up something good...',
  'Baking a fresh response...',
  'Stirring the neural soup...',
  'Seasoning with randomness...',
  'Adding a pinch of creativity...',
  'Taste testing the output...',

  // Self-aware humor
  'Pretending to think...',
  'Acting like I understand...',
  'Nodding along...',
  'Smiling and waving...',
  'Making it look easy...',
  'Furrowing my virtual brow...',
  'Stroking my nonexistent beard...',
  'Adjusting my imaginary glasses...',
  'Looking thoughtful...',
  'Typing dramatically...',
  'Pausing for effect...',
  'Building suspense...',
  'Creating artificial tension...',
  'Buffering emotions...',
  'Loading personality...',
  'Initializing charm...',
  'Booting up wit...',
  'Calibrating sarcasm...',

  // Technical deep cuts
  'Backpropagating feelings...',
  'Vanishing gradient detected...',
  'Exploding gradient contained...',
  'Mode collapsed, trying again...',
  'Escaping local minima...',
  'Saddle point navigation...',
  'Momentum building...',
  'Adam optimizing...',
  'Learning rate scheduling...',
  'Early stopping considered...',
  'Regularizing my thoughts...',
  'L2 normalizing opinions...',
  'Dropout preventing overfitting...',
  'Data augmenting reality...',
  'Feature engineering...',
  'Hyperparameter tuning...',
  'Grid searching for answers...',
  'Random searching instead...',
  'Bayesian optimizing...',
  'AutoML-ing this response...',

  // Modern AI culture
  'Scaling laws go brrr...',
  'Chinchilla optimal thinking...',
  'Emergent abilities emerging...',
  'In-context learning...',
  'Few-shot prompting myself...',
  'Chain of thought activated...',
  'Let\'s think step by step...',
  'Reasoning out loud...',
  'Self-consistency checking...',
  'Constitutional AI-ing...',
  'RLHF-ing my response...',
  'DPO-ing my preferences...',
  'Fine-tuning on the fly...',
  'LoRA adapting...',
  'Quantizing my thoughts to 4-bit...',
  'Running in FP16 mode...',
  'Flash attention engaged...',
  'KV cache warming up...',
  'Speculative decoding...',
  'Mixture of experts convening...',
];

// Fun thinking status messages
const THINKING_MESSAGES = [
  // Classic thinking
  'Thinking...',
  'Hmm, let me think...',
  'Processing...',
  'Contemplating...',
  'Pondering deeply...',
  'Ruminating...',
  'Cogitating...',
  'Deliberating...',
  'Meditating on this...',
  'Reflecting...',

  // Brain metaphors
  'Neurons firing...',
  'Brain cells activating...',
  'Synapses sparking...',
  'Mental gears turning...',
  'Thought bubbles forming...',
  'Idea lightbulb flickering...',
  'Connecting the dots...',
  'Putting 2 and 2 together...',
  'Cogs whirring...',
  'Wheels spinning...',

  // AI/ML thinking
  'Chain of thought loading...',
  'Reasoning chains forming...',
  'Let me think step by step...',
  'Breaking this down...',
  'Analyzing the problem...',
  'Computing implications...',
  'Running thought experiments...',
  'Simulating scenarios...',
  'Weighing the options...',
  'Considering all angles...',
  'Exploring the solution space...',
  'Tree of thoughts growing...',
  'Graph of thoughts connecting...',
  'Self-consistency checking...',
  'Verifying my reasoning...',
  'Double-checking logic...',

  // Funny/quirky
  'Hold on, cooking something up...',
  'Wait, I\'m onto something...',
  'Ooh, interesting question...',
  'Now you\'ve got me thinking...',
  'This requires brain juice...',
  'Activating big brain mode...',
  'Galaxy brain engaged...',
  'Wrinkle forming on brain...',
  '1000 IQ moment incoming...',
  'Trust the process...',
  'Assembling thoughts...',
  'Gathering my wits...',
  'Summoning intelligence...',
  'Channeling inner genius...',
  'Borrowing brain cells...',
  'Defragging the mind...',
  'Rebooting thought processes...',
  'Clearing mental cache...',
  'Loading wisdom.dll...',
  'Initializing smart mode...',

  // Existential thinking
  'What if... no wait...',
  'Actually, hmm...',
  'On second thought...',
  'Let me reconsider...',
  'Rewinding that thought...',
  'Plot twist incoming...',
  'Wait, there\'s more...',
  'Down the rabbit hole...',
  'Inception level thinking...',
  'Thinking about thinking...',
  'Meta-cognition activated...',
  'Recursively pondering...',

  // Pop culture
  'My brain cells in a meeting...',
  'Consulting the council...',
  'The voices are conferring...',
  'Brainstorm in progress...',
  'Idea thunderstorm brewing...',
  'Thought tornado forming...',
  'Mental gymnastics...',
  'Doing cognitive parkour...',
  'Intellectual acrobatics...',
  'Philosophy mode on...',

  // Dramatic
  'The plot thickens...',
  'Dramatic pause...',
  'Suspense building...',
  'Tension mounting...',
  'The gears are turning...',
  'Something\'s brewing...',
  'Eureka moment pending...',
  'Breakthrough imminent...',
  'Discovery loading...',
  'Revelation incoming...',

  // Self-aware
  'Pretending to think deeply...',
  'Looking thoughtful...',
  'Furrowing virtual brow...',
  'Stroking imaginary chin...',
  'Staring into the distance...',
  'Gazing at the ceiling...',
  'Tapping fingers thoughtfully...',
  'Pacing back and forth...',
  'Scribbling on mental notepad...',
  'Drawing thought diagrams...',

  // Silly
  'Asking my rubber duck...',
  'Consulting the magic conch...',
  'Shaking the 8-ball...',
  'Reading tea leaves...',
  'Checking horoscope...',
  'Throwing darts at ideas...',
  'Spinning the wheel of logic...',
  'Rolling for intelligence...',
  'Nat 20 on wisdom check...',
  'Perception check passed...',

  // Technical
  'Reasoning tokens engaged...',
  'Scratchpad filling up...',
  'Internal monologue running...',
  'Hidden chain of thought...',
  'Stealth thinking mode...',
  'Background processing...',
  'Async contemplation...',
  'Parallel reasoning...',
  'Multi-threaded thinking...',
  'Distributed cognition...',
];

export const ChatInput = memo(({ onSend, onAbort, onModelLoad, disabled, isGenerating, autoFocus = false, focusTrigger, isEmptyChat = false, editingMessage, onEditCancel }: ChatInputProps) => {
  const [value, setValue] = useState('');
  const [isModelOpen, setIsModelOpen] = useState(false);
  const [models, setModels] = useState<LLMModel[]>([]);
  const [loadingModels, setLoadingModels] = useState(false);
  const [attachments, setAttachments] = useState<ChatAttachment[]>([]);
  const [isProcessingFile, setIsProcessingFile] = useState(false);
  const [isDragOver, setIsDragOver] = useState(false);
  const dragCounterRef = useRef(0);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const dropdownRef = useRef<HTMLDivElement>(null);
  const modelButtonRef = useRef<HTMLButtonElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [dropdownPosition, setDropdownPosition] = useState({ top: 0, right: 0 });
  const wasGeneratingRef = useRef(false);

  // Animated typewriter placeholder - only animate when input is empty, not disabled, and chat is empty
  const shouldAnimatePlaceholder = !disabled && value.length === 0 && !isGenerating && isEmptyChat;
  const animatedPlaceholder = useTypewriterPlaceholder(shouldAnimatePlaceholder);

  const selectedModel = useChatStore((s) => s.selectedModel);
  const setSelectedModel = useChatStore((s) => s.setSelectedModel);
  const modelStatus = useChatStore((s) => s.modelStatus);
  const thinkingEnabled = useChatStore((s) => s.thinkingEnabled);
  const setThinkingEnabled = useChatStore((s) => s.setThinkingEnabled);
  const internetEnabled = useChatStore((s) => s.internetEnabled);
  const setInternetEnabled = useChatStore((s) => s.setInternetEnabled);
  const artifactEnabled = useChatStore((s) => s.artifactEnabled);
  const setArtifactEnabled = useChatStore((s) => s.setArtifactEnabled);
  const chatStatus = useChatStore((s) => s.chatStatus);
  const chatStatusQuery = useChatStore((s) => s.chatStatusQuery);

  // Animated typewriter for status messages (no delete animation)
  const animatedGeneratingMessage = useTypewriter(GENERATING_MESSAGES, isGenerating === true && chatStatus === 'generating', true);
  const animatedThinkingMessage = useTypewriter(THINKING_MESSAGES, isGenerating === true && chatStatus === 'thinking', true);

  const fileAttachTrigger = useChatStore((s) => s.fileAttachTrigger);
  const getApiBaseUrl = useSettingsStore((s) => s.getApiBaseUrl);

  // Check if attachments require vision and model supports it
  const hasVisionAttachments = useMemo(
    () => attachments.some(a => a.requiresVision),
    [attachments]
  );
  const modelSupportsVision = useMemo(
    () => selectedModel ? isVisionModel(selectedModel) : false,
    [selectedModel]
  );
  const showVisionWarning = hasVisionAttachments && !modelSupportsVision;

  // Focus input on mount or when focusTrigger changes (with delay to account for animations)
  useEffect(() => {
    if (autoFocus || focusTrigger) {
      const timer = setTimeout(() => {
        textareaRef.current?.focus();
      }, 600);
      return () => clearTimeout(timer);
    }
  }, [autoFocus, focusTrigger]);

  // Focus input when generation completes
  useEffect(() => {
    if (wasGeneratingRef.current && !isGenerating && !disabled) {
      textareaRef.current?.focus();
    }
    wasGeneratingRef.current = isGenerating ?? false;
  }, [isGenerating, disabled]);

  // When editing message changes, populate the input
  useEffect(() => {
    if (editingMessage) {
      setValue(editingMessage.content);
      // Focus and move cursor to end after state update
      setTimeout(() => {
        textareaRef.current?.focus();
        if (textareaRef.current) {
          textareaRef.current.selectionStart = textareaRef.current.value.length;
          textareaRef.current.selectionEnd = textareaRef.current.value.length;
          // Trigger auto-resize
          textareaRef.current.style.height = 'auto';
          textareaRef.current.style.height = `${Math.min(textareaRef.current.scrollHeight, 300)}px`;
        }
      }, 0);
    }
  }, [editingMessage]);

  // Listen for file attach trigger from menu
  useEffect(() => {
    if (fileAttachTrigger > 0) {
      fileInputRef.current?.click();
    }
  }, [fileAttachTrigger]);

  // Fetch models when dropdown opens
  useEffect(() => {
    if (isModelOpen && models.length === 0) {
      const fetchModels = async () => {
        setLoadingModels(true);
        try {
          const apiBaseUrl = getApiBaseUrl();
          const response = await fetch(`${apiBaseUrl}/api/models/llms`);
          if (response.ok) {
            const data = await response.json();
            const llmModels: LLMModel[] = (data.models || []).map((m: { name: string; path: string; size_human?: string }) => ({
              name: m.name,
              path: m.path,
              size: m.size_human,
            }));
            setModels(llmModels);
          }
        } catch (err) {
          console.error('Failed to fetch LLM models:', err);
        } finally {
          setLoadingModels(false);
        }
      };
      fetchModels();
    }
  }, [isModelOpen, models.length, getApiBaseUrl]);

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (
        dropdownRef.current &&
        !dropdownRef.current.contains(event.target as Node) &&
        modelButtonRef.current &&
        !modelButtonRef.current.contains(event.target as Node)
      ) {
        setIsModelOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  // Calculate dropdown position when opening
  useEffect(() => {
    if (isModelOpen && modelButtonRef.current) {
      const rect = modelButtonRef.current.getBoundingClientRect();
      setDropdownPosition({
        top: rect.top - 12, // 12px gap above button
        right: window.innerWidth - rect.right,
      });
    }
  }, [isModelOpen]);

  const handleSelectModel = useCallback((model: LLMModel) => {
    setSelectedModel(model.path);
    setIsModelOpen(false);
    onModelLoad?.(model.path);
  }, [setSelectedModel, onModelLoad]);


  // Process files from either file input or drag & drop
  const processFiles = useCallback(async (files: FileList | File[]) => {
    if (!files || files.length === 0) return;

    setIsProcessingFile(true);
    try {
      const newAttachments: ChatAttachment[] = [];
      const skippedFiles: string[] = [];

      for (const file of Array.from(files)) {
        try {
          const attachment = await createAttachment(file);
          if (attachment) {
            console.log('[Attachment]', attachment.name, {
              hasTextContent: !!attachment.textContent,
              textLength: attachment.textContent?.length ?? 0,
              requiresVision: attachment.requiresVision,
            });
            newAttachments.push(attachment);
          } else {
            skippedFiles.push(file.name);
          }
        } catch (err) {
          const message = err instanceof Error ? err.message : `Failed to process ${file.name}`;
          notify.error(message);
          console.error('Error processing file:', file.name, err);
        }
      }

      if (skippedFiles.length > 0) {
        console.warn(`Skipped binary files: ${skippedFiles.join(', ')}`);
      }

      setAttachments(prev => [...prev, ...newAttachments]);
    } catch (err) {
      console.error('Error processing files:', err);
    } finally {
      setIsProcessingFile(false);
    }
  }, []);

  const handleFileSelect = useCallback((e: ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files;
    if (files && files.length > 0) {
      processFiles(files);
    }
    // Reset input so same file can be selected again
    if (fileInputRef.current) {
      fileInputRef.current.value = '';
    }
  }, [processFiles]);

  const handleRemoveAttachment = useCallback((id: string) => {
    setAttachments(prev => prev.filter(a => a.id !== id));
  }, []);

  // Drag and drop handlers (using counter to handle nested elements)
  const handleDragEnter = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    dragCounterRef.current++;
    if (e.dataTransfer.types.includes('Files')) {
      setIsDragOver(true);
    }
  }, []);

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    dragCounterRef.current--;
    if (dragCounterRef.current === 0) {
      setIsDragOver(false);
    }
  }, []);

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
  }, []);

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    dragCounterRef.current = 0;
    setIsDragOver(false);

    const files = e.dataTransfer.files;
    if (files && files.length > 0) {
      processFiles(files);
    }
  }, [processFiles]);

  const handleSend = useCallback(() => {
    const trimmed = value.trim();
    // Allow sending with just attachments (no text) or with text
    if ((trimmed || attachments.length > 0) && !disabled && !isGenerating) {
      onSend(trimmed, attachments.length > 0 ? attachments : undefined);
      setValue('');
      setAttachments([]);
      if (textareaRef.current) {
        textareaRef.current.style.height = 'auto';
      }
    }
  }, [value, attachments, disabled, isGenerating, onSend]);

  const handleAbort = useCallback(() => {
    onAbort?.();
  }, [onAbort]);

  const handleKeyDown = useCallback(
    (e: KeyboardEvent<HTMLTextAreaElement>) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        handleSend();
      }
    },
    [handleSend]
  );

  const handleInput = useCallback(() => {
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto';
      textareaRef.current.style.height = `${Math.min(textareaRef.current.scrollHeight, 300)}px`;
    }
  }, []);

  // Get status message based on current chat status
  const getStatusMessage = () => {
    switch (chatStatus) {
      case 'searching':
        return chatStatusQuery ? `Searching "${chatStatusQuery}"...` : 'Searching the web...';
      case 'thinking':
        return animatedThinkingMessage;
      case 'generating':
        return animatedGeneratingMessage;
      case 'creating':
        return 'Creating document...';
      default:
        return 'Processing...';
    }
  };

  return (
    <div className={`flex flex-col gap-2 ${isGenerating ? 'items-center' : ''}`}>
      {/* Editing message reference */}
      {editingMessage && !isGenerating && (
        <div
          className="flex items-start gap-2 px-3 py-2 rounded-xl text-xs"
          style={{
            background: 'rgba(255, 255, 255, 0.06)',
            border: '1px solid rgba(255, 255, 255, 0.1)',
          }}
        >
          <Pencil className="w-3.5 h-3.5 flex-shrink-0 mt-0.5" style={{ color: 'var(--color-text-muted)' }} />
          <div className="flex-1 min-w-0">
            <div className="text-[11px] mb-1" style={{ color: 'var(--color-text-muted)' }}>
              Editing message
            </div>
            <div
              className="line-clamp-2"
              style={{ color: 'var(--color-text-secondary)' }}
            >
              {editingMessage.content}
            </div>
          </div>
          <button
            onClick={onEditCancel}
            className="p-1 rounded-md transition-colors hover:bg-white/10 cursor-pointer flex-shrink-0"
            style={{ color: 'var(--color-text-secondary)' }}
          >
            <X className="w-3.5 h-3.5" />
          </button>
        </div>
      )}

      {/* Attachment preview area */}
      {attachments.length > 0 && !isGenerating && (
        <div className="flex flex-wrap gap-2 px-2">
          {attachments.map((attachment) => (
            <AttachmentPreview
              key={attachment.id}
              attachment={attachment}
              onRemove={() => handleRemoveAttachment(attachment.id)}
            />
          ))}
        </div>
      )}

      {/* Vision model warning */}
      {showVisionWarning && !isGenerating && (
        <div
          className="flex items-center gap-2 px-3 py-2 rounded-xl text-xs"
          style={{
            background: 'rgba(250, 179, 135, 0.15)',
            color: 'var(--color-peach)',
          }}
        >
          <AlertTriangle className="w-4 h-4 flex-shrink-0" />
          <span>
            Images attached but the selected model may not support vision. Text files will still be processed.
          </span>
        </div>
      )}

      {/* Container with glassmorphism - transforms between input and status pill */}
      <div
        className={cn(
          'relative flex items-center gap-2 px-2 py-2 backdrop-blur-xl transition-all duration-200',
          isGenerating && 'chat-input-generating',
          isDragOver && 'ring-2 ring-[var(--color-accent)] ring-opacity-50'
        )}
        style={{
          background: isDragOver ? 'rgba(255, 255, 255, 0.12)' : 'rgba(255, 255, 255, 0.08)',
          boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
          borderRadius: '32px',
          maxWidth: isGenerating ? '480px' : '100%',
          width: '100%',
          transition: 'max-width 0.7s cubic-bezier(0.34, 1.56, 0.64, 1), background 0.2s ease',
        }}
        onDragEnter={handleDragEnter}
        onDragLeave={handleDragLeave}
        onDragOver={handleDragOver}
        onDrop={handleDrop}
      >
        {isGenerating ? (
          /* Status pill mode - status on left, stop on right */
          <>
            {/* Left side: orb + status text */}
            <div className="flex items-center gap-3 flex-1 px-2">
              {/* Animated orb indicator - Siri-style */}
              <div className="relative w-3.5 h-3.5 flex-shrink-0">
                {/* Pulsing outer glow */}
                <div
                  className="absolute -inset-1.5 rounded-full chat-siri-glow"
                  style={{ filter: 'blur(5px)' }}
                />
                {/* Orb core - Siri gradient */}
                <div className="absolute inset-0 rounded-full chat-siri-orb" />
                {/* Orb highlight */}
                <div
                  className="absolute inset-0 rounded-full"
                  style={{
                    background: 'radial-gradient(circle at 30% 30%, rgba(255,255,255,0.5) 0%, transparent 40%)',
                  }}
                />
              </div>

              {/* Status text */}
              <span
                className="font-medium text-[13px] whitespace-nowrap"
                style={{ color: 'var(--color-text)' }}
              >
                {getStatusMessage()}
              </span>
            </div>

            {/* Right side: Stop button */}
            <TooltipProvider delayDuration={300}>
              <Tooltip>
                <TooltipTrigger asChild>
                  <button
                    onClick={handleAbort}
                    className="flex items-center justify-center w-10 h-10 rounded-full transition-all duration-200 hover:bg-white/10"
                    style={{ color: 'var(--color-text-secondary)' }}
                  >
                    <Square className="w-4 h-4 fill-current" />
                  </button>
                </TooltipTrigger>
                <TooltipContent side="bottom">Stop generating</TooltipContent>
              </Tooltip>
            </TooltipProvider>
          </>
        ) : (
          /* Normal input mode */
          <>
            {/* Hidden file input - no accept filter, we detect text content */}
            <input
              ref={fileInputRef}
              type="file"
              multiple
              onChange={handleFileSelect}
              className="hidden"
            />

            {/* Attachment button */}
            <TooltipProvider delayDuration={300}>
              <Tooltip>
                <TooltipTrigger asChild>
                  <button
                    onClick={() => fileInputRef.current?.click()}
                    disabled={isProcessingFile}
                    className={cn(
                      'flex items-center justify-center w-10 h-10 rounded-full transition-all duration-200 hover:bg-white/10',
                      isProcessingFile && 'opacity-50'
                    )}
                    style={{ color: 'var(--color-text-secondary)' }}
                  >
                    {isProcessingFile ? (
                      <Loader2 className="w-5 h-5 animate-spin" />
                    ) : (
                      <Paperclip className="w-5 h-5" />
                    )}
                  </button>
                </TooltipTrigger>
                <TooltipContent side="bottom">Attach files</TooltipContent>
              </Tooltip>
            </TooltipProvider>

            <textarea
              ref={textareaRef}
              value={value}
              onChange={(e) => setValue(e.target.value)}
              onKeyDown={handleKeyDown}
              onInput={handleInput}
              placeholder={disabled ? 'Select a model to start chatting...' : animatedPlaceholder}
              disabled={disabled}
              rows={1}
              className={cn(
                'flex-1 resize-none bg-transparent pr-4 py-2 text-sm outline-none overflow-y-auto',
                'placeholder:text-[var(--color-text-secondary)]',
                disabled && 'opacity-50 cursor-not-allowed'
              )}
              style={{
                color: 'var(--color-text)',
                maxHeight: 300,
              }}
            />

            {/* Thinking toggle */}
            <TooltipProvider delayDuration={300}>
              <Tooltip>
                <TooltipTrigger asChild>
                  <button
                    onClick={() => setThinkingEnabled(!thinkingEnabled)}
                    className={cn(
                      'flex items-center justify-center w-10 h-10 rounded-full transition-all duration-200',
                      thinkingEnabled ? 'bg-white/15' : 'hover:bg-white/10'
                    )}
                    style={{ color: 'var(--color-text-secondary)' }}
                  >
                    <Lightbulb className="w-5 h-5" />
                  </button>
                </TooltipTrigger>
                <TooltipContent side="bottom">
                  {thinkingEnabled ? 'Thinking enabled' : 'Enable thinking'}
                </TooltipContent>
              </Tooltip>
            </TooltipProvider>

            {/* Internet/Web search toggle */}
            <TooltipProvider delayDuration={300}>
              <Tooltip>
                <TooltipTrigger asChild>
                  <button
                    onClick={() => setInternetEnabled(!internetEnabled)}
                    className={cn(
                      'flex items-center justify-center w-10 h-10 rounded-full transition-all duration-200',
                      internetEnabled ? 'bg-white/15' : 'hover:bg-white/10'
                    )}
                    style={{ color: 'var(--color-text-secondary)' }}
                  >
                    <Globe className="w-5 h-5" />
                  </button>
                </TooltipTrigger>
                <TooltipContent side="bottom">
                  {internetEnabled ? 'Web search enabled' : 'Enable web search'}
                </TooltipContent>
              </Tooltip>
            </TooltipProvider>

            {/* Artifact/Document creation toggle */}
            <TooltipProvider delayDuration={300}>
              <Tooltip>
                <TooltipTrigger asChild>
                  <button
                    onClick={() => setArtifactEnabled(!artifactEnabled)}
                    className={cn(
                      'flex items-center justify-center w-10 h-10 rounded-full transition-all duration-200',
                      artifactEnabled ? 'bg-white/15' : 'hover:bg-white/10'
                    )}
                    style={{ color: 'var(--color-text-secondary)' }}
                  >
                    <FileText className="w-5 h-5" />
                  </button>
                </TooltipTrigger>
                <TooltipContent side="bottom">
                  {artifactEnabled ? 'Document creation enabled' : 'Create document'}
                </TooltipContent>
              </Tooltip>
            </TooltipProvider>

            {/* Model selector */}
            <div className="relative">
              <TooltipProvider delayDuration={300}>
                <Tooltip>
                  <TooltipTrigger asChild>
                    <button
                      ref={modelButtonRef}
                      onClick={() => setIsModelOpen(!isModelOpen)}
                      className="flex items-center justify-center w-10 h-10 rounded-full transition-all duration-100 hover:bg-white/10"
                    >
                      <ModelStatusIcon status={modelStatus} />
                    </button>
                  </TooltipTrigger>
                  <TooltipContent side="bottom">
                    {selectedModel
                      ? `Model: ${models.find(m => m.path === selectedModel)?.name || selectedModel.split('/').pop()}`
                      : 'Select model'}
                  </TooltipContent>
                </Tooltip>
              </TooltipProvider>

              {/* Dropdown - rendered via portal to escape parent's backdrop-filter */}
              {isModelOpen && createPortal(
                <div
                  ref={dropdownRef}
                  className="fixed py-1.5 rounded-xl min-w-[220px] max-h-64 overflow-y-auto backdrop-blur-xl z-50"
                  style={{
                    top: dropdownPosition.top,
                    right: dropdownPosition.right,
                    transform: 'translateY(-100%)',
                    background: 'rgba(255, 255, 255, 0.08)',
                    boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
                  }}
                >
                  {loadingModels ? (
                    <div
                      className="flex items-center justify-center gap-2 px-3 py-4 text-xs"
                      style={{ color: 'var(--color-text-secondary)' }}
                    >
                      <Loader2 className="w-4 h-4 animate-spin" />
                      Loading models...
                    </div>
                  ) : models.length === 0 ? (
                    <div className="px-3 py-3 text-xs text-center">
                      <div style={{ color: 'var(--color-text-secondary)' }}>
                        No LLM models found.
                        <br />
                        <span className="opacity-70">Add .gguf files to models/llm/</span>
                      </div>
                      <button
                        onClick={() => {
                          setIsModelOpen(false);
                          useDownloadStore.getState().openModalToCategory('llms');
                        }}
                        className="flex items-center justify-center gap-2 w-full mt-2 px-3 py-1.5 rounded-lg transition-colors hover:bg-white/10"
                        style={{ color: 'var(--color-accent)' }}
                      >
                        <Download className="w-4 h-4" />
                        <span>Download models</span>
                      </button>
                    </div>
                  ) : (
                    <>
                      {models.map((model) => {
                        const isSelected = model.path === selectedModel;
                        return (
                          <button
                            key={model.path}
                            onClick={() => handleSelectModel(model)}
                            className={cn(
                              'flex items-center gap-2 w-[calc(100%-12px)] mx-1.5 px-3 py-1.5 text-xs text-left rounded-lg transition-colors',
                              'hover:bg-white/10'
                            )}
                            style={{
                              color: 'var(--color-text)',
                              opacity: isSelected ? 1 : 0.5,
                            }}
                          >
                            <div className="flex-1 min-w-0">
                              <div className="truncate">{model.name}</div>
                              {model.size && (
                                <div
                                  className="text-[11px]"
                                  style={{ color: 'var(--color-text-secondary)' }}
                                >
                                  {model.size}
                                </div>
                              )}
                            </div>
                            {isSelected && (
                              <Check
                                className="w-4 h-4 flex-shrink-0"
                                style={{ color: 'var(--color-accent)' }}
                              />
                            )}
                          </button>
                        );
                      })}
                      {/* Divider and Get more button */}
                      <div className="mx-1.5 my-1 border-t border-white/10" />
                      <button
                        onClick={() => {
                          setIsModelOpen(false);
                          useDownloadStore.getState().openModalToCategory('llms');
                        }}
                        className="flex items-center gap-2 w-[calc(100%-12px)] mx-1.5 px-3 py-1.5 text-xs text-left rounded-lg transition-colors hover:bg-white/10"
                        style={{ color: 'var(--color-text-secondary)' }}
                      >
                        <Download className="w-4 h-4" />
                        <span>Get more models...</span>
                      </button>
                    </>
                  )}
                </div>,
                document.body
              )}
            </div>
          </>
        )}
      </div>
    </div>
  );
});

function ModelStatusIcon({ status }: { status: ModelStatus }) {
  if (status === 'loading') {
    return (
      <Loader2
        className="w-5 h-5 animate-spin"
        style={{ color: 'var(--color-text-secondary)' }}
      />
    );
  }
  return (
    <Sparkles
      className="w-5 h-5"
      style={{ color: 'var(--color-text-secondary)' }}
    />
  );
}

ChatInput.displayName = 'ChatInput';

/**
 * Attachment preview chip component.
 */
interface AttachmentPreviewProps {
  attachment: ChatAttachment;
  onRemove: () => void;
}

const AttachmentPreview = memo(({ attachment, onRemove }: AttachmentPreviewProps) => {
  const isImage = attachment.requiresVision;

  return (
    <div
      className="flex items-center gap-2 px-3 py-1.5 rounded-full text-xs backdrop-blur-xl group"
      style={{
        background: 'rgba(255, 255, 255, 0.08)',
        color: 'var(--color-text)',
      }}
    >
      {isImage && attachment.dataUrl ? (
        <img
          src={attachment.dataUrl}
          alt={attachment.name}
          className="w-5 h-5 rounded object-cover"
        />
      ) : (
        <FileText className="w-4 h-4" style={{ color: 'var(--color-text-secondary)' }} />
      )}
      <span className="max-w-[120px] truncate">{attachment.name}</span>
      <span style={{ color: 'var(--color-text-muted)' }}>
        {formatFileSize(attachment.size)}
      </span>
      <button
        onClick={onRemove}
        className="flex items-center justify-center w-4 h-4 rounded-full hover:bg-white/20 transition-colors"
        style={{ color: 'var(--color-text-secondary)' }}
      >
        <X className="w-3 h-3" />
      </button>
    </div>
  );
});

AttachmentPreview.displayName = 'AttachmentPreview';
