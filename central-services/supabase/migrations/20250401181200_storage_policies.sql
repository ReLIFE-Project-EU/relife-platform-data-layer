create policy "Enable insert for authenticated users only" on "storage"."objects" as permissive for
insert
    to authenticated with check (true);

create policy "Enable delete for users based on user id" on "storage"."objects" as permissive for delete to public using (
    (
        (
            SELECT
                auth.uid () AS uid
        ) = owner_id :: uuid
    )
);

create policy "Enable insert for users based on user id" on "storage"."objects" as permissive for
insert
    to public with check (
        (
            (
                SELECT
                    auth.uid () AS uid
            ) = owner_id :: uuid
        )
    );

create policy "Enable update for users based on user id" on "storage"."objects" as permissive for
update
    to public using (
        (
            (
                SELECT
                    auth.uid () AS uid
            ) = owner_id :: uuid
        )
    ) with check (
        (
            (
                SELECT
                    auth.uid () AS uid
            ) = owner_id :: uuid
        )
    );

create policy "Enable users to view their own data only" on "storage"."objects" as permissive for
select
    to authenticated using (
        (
            (
                SELECT
                    auth.uid () AS uid
            ) = owner_id :: uuid
        )
    );