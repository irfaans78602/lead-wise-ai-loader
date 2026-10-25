UPDATE clients
SET logo_light_svg = $svg$<svg xmlns="http://www.w3.org/2000/svg" role="img" aria-label="LeadWise AI - Generate, Qualify, Convert" viewBox="0 0 820 220"><path fill="#2bb673" d="M120 20C65 20 20 62 20 115c0 30 14 57 36 75l-40 34 88-16c6 2 11 3 16 3 55 0 100-42 100-96 0-53-45-95-100-95"/><path fill="none" stroke="#fff" stroke-linecap="round" stroke-linejoin="round" stroke-width="16" d="m80 115 30 30 50-55"/><text x="470" y="115" fill="#2bb673" font-family="Inter, Arial, sans-serif" font-size="64" font-weight="800" letter-spacing="-.5" text-anchor="middle">LeadWise AI</text><text x="470" y="168" fill="#6b7280" font-family="Inter, Arial, sans-serif" font-size="28" font-weight="600" letter-spacing="1" text-anchor="middle">GENERATE, QUALIFY, CONVERT</text></svg>$svg$
WHERE client_id = '35d69a44-9649-5556-81a0-251ab6dc537b';

UPDATE clients
SET favicon_svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200"><path fill="#2bb673" d="M100 20C45 20 0 62 0 115c0 30 14 57 36 75l-40 34 88-16c6 2 11 3 16 3 55 0 100-42 100-96 0-53-45-95-100-95"/><path fill="none" stroke="#fff" stroke-linecap="round" stroke-linejoin="round" stroke-width="16" d="m60 115 30 30 50-55"/></svg>'
WHERE client_id = '35d69a44-9649-5556-81a0-251ab6dc537b';

