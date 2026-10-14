"""AI providers. Each returns the same structured ModelAnswer; none of them receives row data.

Settings precedence: a non-empty environment variable wins, then the value stored in app state
(secrets decrypted only here, in memory), then the default."""
import logging, os
import httpx
from pydantic import BaseModel, Field, ValidationError
from .state import SecretUnavailable, mask

log = logging.getLogger('querywise.providers')
PROVIDERS = ('demo', 'ollama', 'anthropic')
if os.getenv('AI_PROVIDER', '').strip() not in ('', *PROVIDERS): raise RuntimeError('AI_PROVIDER must be demo, ollama or anthropic.')
EFFORTS = ('low', 'medium', 'high', 'xhigh', 'max')
# Models that accept the server-side refusal fallback (`fallbacks: "default"`).
FALLBACK_MODELS = {'claude-fable-5-1', 'claude-opus-5-5', 'claude-opus-5', 'claude-sonnet-5-5'}
SETTINGS = {  # name: (environment variable, default, secret)
    'provider': ('AI_PROVIDER', 'demo', False),
    'anthropic_api_key': ('ANTHROPIC_API_KEY', '', True),
    'anthropic_model': ('ANTHROPIC_MODEL', 'claude-opus-5-5', False),
    # Needed when the API key is not scoped to a workspace (sent as the anthropic-workspace-id header).
    'anthropic_workspace_id': ('ANTHROPIC_WORKSPACE_ID', '', False),
    'anthropic_effort': ('ANTHROPIC_EFFORT', 'medium', False),
    'ollama_url': ('OLLAMA_URL', None, False),
    'ollama_model': ('OLLAMA_MODEL', 'qwen2.5:7b', False),
}

class ModelAnswer(BaseModel):
    sql: str = Field(max_length=12000)
    title: str = Field(max_length=100)
    explanation: str = Field(max_length=1200)
    chart: str = Field(pattern='^(bar|line|table)$')
    clarification: str = Field(default='', max_length=500)

# Plain JSON schema for Claude structured outputs (length limits are enforced by ModelAnswer afterwards).
ANSWER_SCHEMA = {'type': 'object', 'additionalProperties': False, 'required': ['sql', 'title', 'explanation', 'chart', 'clarification'],
                 'properties': {'sql': {'type': 'string'}, 'title': {'type': 'string'}, 'explanation': {'type': 'string'},
                                'chart': {'type': 'string', 'enum': ['bar', 'line', 'table']}, 'clarification': {'type': 'string'}}}

class ProviderError(Exception):
    def __init__(self, status, message): super().__init__(message); self.status, self.message = status, message

def setting(state, name):
    """(value, origin) with origin env | stored | default | unreadable."""
    env, default, secret = SETTINGS[name]
    if default is None: default = os.getenv('OLLAMA_DEFAULT_URL', 'http://localhost:11434')
    value = os.getenv(env, '').strip()
    if value: return value, 'env'
    try: stored = state.get(name)
    except SecretUnavailable: return default, 'unreadable'
    return (stored, 'stored') if stored else (default, 'default')

def current(state):
    values = {name: setting(state, name)[0] for name in SETTINGS}
    if values['provider'] not in PROVIDERS: values['provider'] = 'demo'
    if values['anthropic_effort'] not in EFFORTS: values['anthropic_effort'] = 'medium'
    return values

def public(state):
    out = {}
    for name, (env, _, secret) in SETTINGS.items():
        value, origin = setting(state, name)
        out[name] = {'set': bool(value), 'masked': mask(value), 'origin': origin, 'env': env, 'locked': origin == 'env'} if secret else {'value': value, 'origin': origin, 'env': env, 'locked': origin == 'env'}
    return out

def model_name(values):
    return values['anthropic_model'] if values['provider'] == 'anthropic' else values['ollama_model'] if values['provider'] == 'ollama' else None

def parse(text):
    try: return ModelAnswer.model_validate_json(text)
    except (ValueError, ValidationError) as e: raise ProviderError(502, 'The model did not return a valid structured answer. Try a clearer question.') from e

async def ask_ollama(values, system, question):
    try:
        async with httpx.AsyncClient(timeout=90) as client:
            response = await client.post(values['ollama_url'].rstrip('/') + '/api/chat', json={'model': values['ollama_model'], 'stream': False, 'messages': [{'role': 'system', 'content': system}, {'role': 'user', 'content': question}],
                                         'format': ModelAnswer.model_json_schema(), 'options': {'temperature': 0, 'num_predict': 1200}})
            response.raise_for_status()
        return parse(response.json()['message']['content'])
    except httpx.HTTPError as e: raise ProviderError(502, 'Ollama is unavailable or the model is not installed. Check the Ollama URL and run ollama pull for the configured model.') from e
    except (KeyError, TypeError) as e: raise ProviderError(502, 'The model did not return a valid structured answer. Try a clearer question.') from e

def anthropic_client(values):
    if not values['anthropic_api_key']: raise ProviderError(503, 'Anthropic mode needs an API key. Paste it in Settings or set ANTHROPIC_API_KEY.')
    import anthropic
    headers = {'anthropic-workspace-id': values['anthropic_workspace_id']} if values.get('anthropic_workspace_id') else None
    return anthropic, anthropic.AsyncAnthropic(api_key=values['anthropic_api_key'], timeout=120, max_retries=1, default_headers=headers)

def anthropic_error(anthropic, e):
    """Map SDK errors to safe API errors. Messages never include the key."""
    if isinstance(e, anthropic.AuthenticationError): return ProviderError(502, 'Anthropic rejected the API key. Check it in Settings or ANTHROPIC_API_KEY.')
    if isinstance(e, anthropic.PermissionDeniedError): return ProviderError(502, 'This Anthropic API key is not allowed to use the configured model.')
    if isinstance(e, anthropic.NotFoundError): return ProviderError(502, 'The configured Claude model was not found. Check ANTHROPIC_MODEL or the model in Settings.')
    if isinstance(e, anthropic.RateLimitError): return ProviderError(503, 'Anthropic rate limit reached. Wait a moment and try again.')
    if isinstance(e, anthropic.APITimeoutError): return ProviderError(504, 'Claude did not answer in time. Try again or simplify the question.')
    if isinstance(e, anthropic.APIConnectionError): return ProviderError(502, 'Cannot reach the Anthropic API. Check your network connection.')
    if isinstance(e, anthropic.APIStatusError):
        # Anthropic's own explanation (it never echoes the API key) is what makes a 400 actionable.
        detail = ''
        body = e.body if isinstance(getattr(e, 'body', None), dict) else {}
        message = (body.get('error') or {}).get('message') if isinstance(body.get('error'), dict) else None
        detail = (message or str(getattr(e, 'message', '')) or '').strip()[:400]
        log.warning('Anthropic API error %s: %s', e.status_code, detail)
        return ProviderError(502, f'Anthropic API error ({e.status_code}): {detail}' if detail else f'Anthropic API error ({e.status_code}). Try again shortly.')
    return ProviderError(502, 'The Anthropic request failed.')

async def ask_anthropic(values, system, question):
    anthropic, client = anthropic_client(values)
    model = values['anthropic_model']
    request = {'model': model, 'max_tokens': 16000, 'system': system, 'messages': [{'role': 'user', 'content': question}],
               'output_config': {'format': {'type': 'json_schema', 'schema': ANSWER_SCHEMA}, 'effort': values['anthropic_effort']}}
    try:
        async with client:
            if model in FALLBACK_MODELS and os.getenv('ANTHROPIC_FALLBACKS', 'on').lower() != 'off':
                # On a safety-classifier refusal the API re-runs the request on a fallback model inside the same call.
                response = await client.beta.messages.create(betas=['server-side-fallback-2026-07-01'], fallbacks='default', **request)
            else: response = await client.messages.create(**request)
    except anthropic.APIError as e: raise anthropic_error(anthropic, e) from e
    if response.stop_reason == 'refusal': raise ProviderError(422, 'Claude declined to answer this question. Rephrase it as a data question about the connected source.')
    if response.stop_reason == 'max_tokens': raise ProviderError(502, 'The model answer was cut off. Try a narrower question.')
    text = next((b.text for b in response.content if b.type == 'text'), '')
    return parse(text)

async def generate(values, system, question):
    if values['provider'] == 'anthropic': return await ask_anthropic(values, system, question)
    if values['provider'] == 'ollama': return await ask_ollama(values, system, question)
    raise ProviderError(503, 'AI mode is disabled. Choose Ollama or Anthropic in Settings (or set AI_PROVIDER), or select a sample question.')

async def check(values):
    """Verify provider configuration without generating text."""
    if values['provider'] == 'anthropic':
        anthropic, client = anthropic_client(values)
        try:
            async with client: await client.models.retrieve(values['anthropic_model'])
        except anthropic.APIError as e: raise anthropic_error(anthropic, e) from e
        return f'Anthropic API key accepted; model {values["anthropic_model"]} is available.'
    if values['provider'] == 'ollama':
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                r = await client.get(values['ollama_url'].rstrip('/') + '/api/tags'); r.raise_for_status()
            names = {m.get('name') for m in r.json().get('models', [])} | {m.get('model') for m in r.json().get('models', [])}
        except (httpx.HTTPError, ValueError) as e: raise ProviderError(502, 'Ollama is not reachable at the configured URL.') from e
        model = values['ollama_model']
        if model not in names and f'{model}:latest' not in names: raise ProviderError(502, f'Ollama is running but the model {model} is not installed. Run: ollama pull {model}')
        return f'Ollama is reachable and {model} is installed.'
    return 'Demo mode needs no model.'
