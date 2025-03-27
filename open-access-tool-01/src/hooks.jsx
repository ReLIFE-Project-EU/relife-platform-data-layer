import { useEffect, useState } from "react";
import { supabase } from "./auth";

export function useSupabaseSession() {
  const [session, setSession] = useState(null);

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
    });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session);
    });

    return () => subscription.unsubscribe();
  }, []);

  return session;
}

export function useWhoami(session, withRoles = true) {
  const [whoami, setWhoami] = useState(null);
  const [error, setError] = useState(null);
  const [fullName, setFullName] = useState(null);

  useEffect(() => {
    if (!session?.access_token) {
      setWhoami(null);
      return;
    }

    fetch(withRoles ? "/api/whoami-with-roles" : "/api/whoami", {
      headers: {
        Authorization: `Bearer ${session.access_token}`,
      },
    })
      .then(async (response) => {
        const data = await response.json();
        return response.ok ? data : Promise.reject(data);
      })
      .then((data) => {
        setWhoami(data);
        setFullName(data?.user?.user?.user_metadata?.full_name);
        setError(null);
      })
      .catch((err) => {
        console.error("Error fetching whoami:", err);
        setError(err);
        setWhoami(null);
        setFullName(null);
      });
  }, [session?.access_token, withRoles]);

  return { whoami, error, fullName };
}
