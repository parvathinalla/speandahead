import json
import httpx
import pytest
import agent_service


@pytest.mark.asyncio
@pytest.mark.parametrize('case', ['complete', 'truncated', 'rate_limit'])
async def test_chat_filters_thoughts_and_handles_incomplete_output(monkeypatch, case):
    original = httpx.AsyncClient
    def handle(request):
        payload = json.loads(request.content)
        assert payload['generationConfig']['thinkingConfig']['thinkingLevel'] == 'low'
        assert payload['generationConfig']['maxOutputTokens'] >= 1600
        if case == 'rate_limit':
            return httpx.Response(429, json={'error': {'status': 'RESOURCE_EXHAUSTED'}})
        return httpx.Response(200, json={'candidates': [{
            'finishReason': 'MAX_TOKENS' if case == 'truncated' else 'STOP',
            'content': {'parts': [{'thought': True, 'text': 'private reasoning'},
                                  {'text': 'How much can you save monthly?'}]}}]})
    monkeypatch.setattr(agent_service.httpx, 'AsyncClient',
                        lambda **kwargs: original(transport=httpx.MockTransport(handle), **kwargs))
    monkeypatch.setenv('GEMINI_API_KEY', 'fictional-test-key')
    monkeypatch.setenv('GEMINI_CHAT_MODEL', 'gemini-3.8-flash')
    reply, used = await agent_service.ask_gemini('When can I buy it?', {}, [], [])
    assert 'private reasoning' not in reply
    assert used == (case == 'complete')
    if case == 'rate_limit':
        assert 'request limit' in reply
