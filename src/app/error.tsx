'use client';
export default function ErrorPage({reset}:{reset:()=>void}){return <main className="center-page"><section className="card"><h1>No pudimos cargar esta página</h1><p>Inténtalo nuevamente. Si el problema continúa, contacta a Administración.</p><button className="button" onClick={reset}>Reintentar</button></section></main>;}
