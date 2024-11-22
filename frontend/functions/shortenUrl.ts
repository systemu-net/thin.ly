import type { Config } from "@netlify/functions";

const apiKey = process.env.URL_KEY;

export default async (req: Request) => {
  const urlParams = new URLSearchParams(await req.text());
  const url = urlParams.get('url');

  if (!url) {
    return new Response('URL is required', { status: 400, headers: { 'Content-Type': 'text/plain' } });
  }

  if (!apiKey) {
    return new Response('API Key is required', { status: 500, headers: { 'Content-Type': 'text/plain' } });
  }

  const headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'x-api-key': apiKey,
  };

  const inputBody = JSON.stringify({
    url: url,
    expiry: '5m'
  });


  try {
    const response = await fetch('https://api.manyapis.com/v1-create-short-url',
      {
        method: 'POST',
        body: inputBody,
        headers: headers
      }
    );

    const data = await response.json();
    console.log(data);
    return new Response(JSON.stringify(data), { status: 200, headers: { 'Content-Type': 'application/json' } });
  } catch {
    return new Response(JSON.stringify({ error: 'Failed to shorten URL'}), { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
}

export const config:Config = {
  path: '/api/*'
}