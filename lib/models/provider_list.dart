import 'provider_config.dart';

/// Built-in AI provider definitions.
///
/// Each entry is a pre-configured [ProviderConfig] with the well-known
/// base URL for that provider. API keys are left null so the user must
/// supply them via the UI or config file.
List<ProviderConfig> builtInProviders() {
  return [
    ProviderConfig(
      id: 'deepseek',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      models: ['deepseek-chat', 'deepseek-reasoner'],
      priority: 10,
      quotaLimit: null,
    ),
    ProviderConfig(
      id: 'openai',
      name: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      models: [
        'gpt-4o',
        'gpt-4o-mini',
        'gpt-4-turbo',
        'gpt-3.5-turbo',
      ],
      priority: 9,
      quotaLimit: null,
    ),
    ProviderConfig(
      id: 'claude',
      name: 'Claude (Anthropic)',
      baseUrl: 'https://api.anthropic.com/v1',
      models: [
        'claude-3-5-sonnet-20241022',
        'claude-3-opus-20240229',
        'claude-3-haiku-20240307',
      ],
      priority: 8,
      quotaLimit: null,
    ),
    ProviderConfig(
      id: 'gemini',
      name: 'Gemini (Google)',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      models: [
        'gemini-2.0-flash',
        'gemini-1.5-pro',
        'gemini-1.5-flash',
      ],
      priority: 7,
      quotaLimit: null,
    ),
    ProviderConfig(
      id: 'grok',
      name: 'Grok (xAI)',
      baseUrl: 'https://api.x.ai/v1',
      models: ['grok-2', 'grok-beta'],
      priority: 6,
      quotaLimit: null,
    ),
    ProviderConfig(
      id: 'nvidia',
      name: 'NVIDIA NIM',
      baseUrl: 'https://api.nvcf.nvidia.com/v1',
      models: [
        'nvidia/llama-3.1-nemotron-70b-instruct',
        'nvidia/mistral-large',
      ],
      priority: 5,
      quotaLimit: null,
    ),
  ];
}
