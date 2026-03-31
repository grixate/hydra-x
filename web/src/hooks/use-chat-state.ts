import { useState, useCallback } from "react";
import { api } from "@/lib/api";
import type { ChatTab } from "@/components/chat/chat-tabs";

export function useChatState(projectId: number, defaultAgent = "memory") {
  const [chatTabs, setChatTabs] = useState<ChatTab[]>([
    { agent: defaultAgent, conversationId: null, messages: [], unread: 0 },
  ]);
  const [activeTabIndex, setActiveTabIndex] = useState(0);
  const [chatCardOpen, setChatCardOpen] = useState(false);
  const [chatCardMinimized, setChatCardMinimized] = useState(false);

  const activeTab = chatTabs[activeTabIndex];

  const handleChatSubmit = useCallback(
    async (message: string, _agent: string, _contextNodeIds: string[]) => {
      if (!chatCardOpen) setChatCardOpen(true);
      if (chatCardMinimized) setChatCardMinimized(false);

      const now = new Date().toISOString();
      setChatTabs((prev) => {
        const next = [...prev];
        next[activeTabIndex] = {
          ...next[activeTabIndex],
          messages: [
            ...next[activeTabIndex].messages,
            { role: "user", content: message, timestamp: now },
          ],
          unread: 0,
        };
        return next;
      });

      try {
        let convId = chatTabs[activeTabIndex].conversationId;
        if (!convId) {
          const conv = await api.createConversation(projectId, {
            persona: chatTabs[activeTabIndex].agent,
            title: "Chat",
          });
          convId = conv.id;
          setChatTabs((prev) => {
            const next = [...prev];
            next[activeTabIndex] = { ...next[activeTabIndex], conversationId: convId };
            return next;
          });
        }

        const result = await api.sendConversationMessage(projectId, convId, message);
        const responseNow = new Date().toISOString();

        if (result.response?.content) {
          setChatTabs((prev) => {
            const next = [...prev];
            next[activeTabIndex] = {
              ...next[activeTabIndex],
              messages: [
                ...next[activeTabIndex].messages,
                { role: "assistant", content: result.response.content!, timestamp: responseNow },
              ],
              unread: chatCardMinimized ? next[activeTabIndex].unread + 1 : 0,
            };
            return next;
          });
        }
      } catch {
        const errorNow = new Date().toISOString();
        setChatTabs((prev) => {
          const next = [...prev];
          next[activeTabIndex] = {
            ...next[activeTabIndex],
            messages: [
              ...next[activeTabIndex].messages,
              { role: "assistant", content: "Sorry, something went wrong.", timestamp: errorNow },
            ],
          };
          return next;
        });
      }
    },
    [chatCardOpen, chatCardMinimized, activeTabIndex, chatTabs, projectId],
  );

  const handleAgentChange = useCallback(
    (agent: string) => {
      const existingIdx = chatTabs.findIndex((t) => t.agent === agent);
      if (existingIdx >= 0) {
        setActiveTabIndex(existingIdx);
      } else {
        setChatTabs((prev) => [
          ...prev,
          { agent, conversationId: null, messages: [], unread: 0 },
        ]);
        setActiveTabIndex(chatTabs.length);
      }
    },
    [chatTabs],
  );

  const handleAddTab = useCallback(
    (agent: string) => {
      setChatTabs((prev) => [
        ...prev,
        { agent, conversationId: null, messages: [], unread: 0 },
      ]);
      setActiveTabIndex(chatTabs.length);
      if (!chatCardOpen) setChatCardOpen(true);
      if (chatCardMinimized) setChatCardMinimized(false);
    },
    [chatTabs.length, chatCardOpen, chatCardMinimized],
  );

  const handleTabClick = useCallback((index: number) => {
    setActiveTabIndex(index);
    setChatTabs((prev) => {
      const next = [...prev];
      next[index] = { ...next[index], unread: 0 };
      return next;
    });
  }, []);

  return {
    chatTabs,
    activeTabIndex,
    activeTab,
    chatCardOpen,
    chatCardMinimized,
    setChatCardOpen,
    setChatCardMinimized,
    handleChatSubmit,
    handleAgentChange,
    handleAddTab,
    handleTabClick,
  };
}
