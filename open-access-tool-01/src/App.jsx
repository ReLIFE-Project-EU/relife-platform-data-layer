import { createClient } from "@supabase/supabase-js";
import { useEffect, useState } from "react";
import "./App.css";
import reactLogo from "./assets/react.svg";
import viteLogo from "/vite.svg";

const ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY;

function getClient() {
  const supabaseUrl = "http://localhost:8000";
  const supabaseKey = ANON_KEY;
  return createClient(supabaseUrl, supabaseKey);
}

async function signInWithKeycloak({ supabase }) {
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: "keycloak",
    options: {
      scopes: "openid",
    },
  });

  console.log("data", data);
  console.log("error", error);
}

const supabase = getClient();

function App() {
  const [count, setCount] = useState(0);
  const [session, setSession] = useState(null);

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      console.log("session", session);
      setSession(session);
    });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      console.log("session", session);
      setSession(session);
    });

    return () => subscription.unsubscribe();
  }, []);

  const handleLogin = async () => {
    await signInWithKeycloak({ supabase });
  };

  return (
    <>
      <button onClick={handleLogin}>Sign In with Keycloak</button>
      <div>
        <a href="https://vite.dev" target="_blank">
          <img src={viteLogo} className="logo" alt="Vite logo" />
        </a>
        <a href="https://react.dev" target="_blank">
          <img src={reactLogo} className="logo react" alt="React logo" />
        </a>
      </div>
      <h1>Vite + React</h1>
      <div className="card">
        <button onClick={() => setCount((count) => count + 1)}>
          count is {count}
        </button>
        <p>
          Edit <code>src/App.jsx</code> and save to test HMR
        </p>
      </div>
      <p className="read-the-docs">
        Click on the Vite and React logos to learn more
      </p>
    </>
  );
}

export default App;
