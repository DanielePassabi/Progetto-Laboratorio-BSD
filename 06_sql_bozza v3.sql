
-- CHANGELOG from v2 to v3
-- addedo unique on Esemplare.gabbia --> senza unique: più animali nella stessa gabbia....
-- creato trigger e relativa funzione per la condizione n° 1 e 3
-- creato trigger e relativa funzione per la condizione n° 2


create table Area(
    nome                varchar(32),
    numero_abitazioni   integer check(numero_abitazioni>=0) not null,

    constraint pk_area primary key(nome)
); -- aggiungere trigger per calcolo numero abitazioni

create table Genere(
    nome    varchar(32),
    
    constraint pk_Genere primary key (nome)
);

create table Abitazione(
    id              oid, -- PostgreSQL Object IDentifier type
    genere          varchar(32) not null,  
    numero_gabbie   integer check(numero_gabbie>=0) not null,
    area            varchar(32) not null,

    constraint pk_Abitazione primary key (id),
    constraint fk_genere_Abitazione_Genere foreign key (genere) references Genere(nome)
        on delete restrict
        on update cascade,
    constraint fk_area_Abitazione_Area foreign key (area) references Area(nome)
        on delete restrict
        on update cascade
);

create table Gabbia(
    id          oid, -- PostgreSQL Object IDentifier type
    abitazione  oid not null,

    constraint pk_Gabbia primary key (id),
    constraint fk_abitazione_Gabbia_Abitazione foreign key (abitazione) references Abitazione(id)
        on delete restrict
        on update cascade
);

create table Esemplare(
    id                  oid, -- PostgreSQL Object IDentifier type
    genere              varchar(32),
    nome                varchar(32) not null,
    sesso               varchar(1) check(sesso IN ( 'F' , 'M' )) not null, --check alternative data type
    paese_provenienza   varchar(32) not null,
    data_nascita        date,
    data_arrivo         date not null,
    gabbia              oid unique not null,

    constraint pk_Esemplare primary key(id,genere),
    constraint fk_genere_Esemplare_Genere foreign key (genere) references Genere(nome)
        on delete restrict
        on update cascade,
    constraint fk_gabbia_Esemplare_Gabbia foreign key (gabbia) references Gabbia(id)
        on delete restrict
        on update cascade
);

create table Addetto_pulizie(
    CF              char(16), --check alternative data type (trigger: check if CF is valid)
    nome            varchar(32) not null, 
    cognome         varchar(32) not null, 
    stipendio       integer check(stipendio >= 0) not null, 
    telefono        varchar(16), 
    turno_pulizia   varchar(64) not null, -- do an entity?

    constraint pk_Addetto_pulizie primary key (CF)
);

create table Pulire(
    addetto_pulizie     char(16),
    abitazione          oid,

    constraint pk_Pulire primary key (addetto_pulizie,abitazione),
    constraint fk_addetto_pulizie_Pulire_Addetto_pulizie foreign key (addetto_pulizie) references Addetto_pulizie(CF)
        on delete cascade
        on update cascade,
    constraint fk_abitazione_Pulire_Abitazione foreign key (abitazione) references Abitazione(id) 
        on delete cascade
        on update cascade
);


create table Veterinario(
    CF              char(16), --check alternative data type (trigger: check if CF is valid)
    nome            varchar(32) not null, 
    cognome         varchar(32) not null, 
    stipendio       integer check(stipendio >= 0) not null, 
    telefono        varchar(16), 
    turno_pulizia   varchar(1024) not null, -- do an entity?

    constraint pk_Veterinario primary key (CF)
);

create table Visita(
    veterinario     varchar(32), 
    esemplare_id    oid, 
    esemplare_gen   varchar(32), 
    data            date,
    peso            integer check(peso > 0) not null, 
    diagnostica     varchar(1024) not null, 
    dieta           varchar(1024) not null,

    constraint pk_Visita primary key (veterinario,esemplare_id,esemplare_gen,data),
    constraint fk_veterinario_Visita_Veterinario foreign key (veterinario) references Veterinario(CF)
        on delete restrict
        on update cascade,
    constraint fk_esemplare_gen_Visista_Genere foreign key (esemplare_gen,esemplare_id) references Esemplare(genere,id) 
        on delete cascade --se un esemplare muore, cancello tutte le visiste eseguite
        on update cascade
);

------------------------------------------------------------------------------------------------------------------------------
-- TRIGGERS --

create trigger aggiunta_modifica_esemplare -- checks n° 1 & 3
before insert or update on Esemplare
for each row
execute procedure aggiunta_modifica_esemplare();

create trigger modifica_gabbia -- checks n° 2
before update on Gabbia
for each row
execute procedure modifica_gabbia();

create trigger aggiunta_modifica_visita -- checks n° 4
before insert or update on Visista
for each row
execute procedure aggiunta_modifica_visita();

create trigger modifica_genere_abitazione -- checks n° 5
before update on Abitazione
for each row
execute procedure modifica_genere_abitazione();

------------------------------------------------------------------------------------------------------------------------------
-- TRIGGERS SQL FUNCTIONS --


-- 1) All'aggiunta (INSERT/UPDATE) di un esemplare ad una gabbia bisogna controllare che l'abitazione in cui essa sia contenuta abbia il genere corretto.
-- 3) All'aggiunta (INSERT/UPDATE) di un esemplare bisogna controllare che data arrivo > data nascita.
create or replace function aggiunta_modifica_esemplare() -- checks n° 1 & 3
returns trigger
as
$$
begin

    perform *
    from(select    A.genere -- ottengo il genere assegnato all'abitazione contenente la gabbia.
        from       Abitazione A
        where      A.id IN(select    G.abitazione -- ottengo l'id dell'abit. della gabbia in cui sto inserendo l'esemp.
                             from    Gabbia G
                            where    G.id = new.gabbia)) genere_ok
    where new.genere = genere_ok.genere;

     if found then
       return NEW;
    end if;
       raise exception 'Record non valido; viola il vincolo di genere! La gabbia in cui stai inserendo l"esemplare è contenuta in un abitazione a cui è stato assegnato un genere diverso da quello dell"esemplare';

end;
$$ language plpgsql;

-- 2) Alla modifica (spostamento) (UPDATE) di una gabbia in una abitazione, bisogna controllare che il genere dell'animale in essa contenuto combaci con quello assegnato alla nuova abitazione di dest.
create or replace function modifica_gabbia() -- checks n° 2
returns trigger
as
$$
begin -- CASO 1: gabbia con un esemplare assegnato

    perform *
	from(select  E.genere  -- ottengo il genere dell'esemplare assegnato alla gabbia che sto spostando
         from    Esemplare E
         where   E.gabbia IN(select  G.id
                             from    Gabbia G
                             where   G.id = new.id)) genere_esemplare
	where (genere_esemplare.genere IN(select   A.genere -- ottengo il genere assegnato all'abitazione in cui sto cercando di spostare/aggiungere la gabbia
                                       from    Abitazione A
                                      where    A.id = new.abitazione));  -- Se la gabbia è vuota, bisogna poterla spostare

    if found then
       return NEW;
    end if;
	
	begin -- CASO 2: gestione del caso in cui la gabbia da spostare è vuota, di conseguenza il CASO 1 ritornerà false su "if found" ma la gabbia può comunque essere spostata perchè è vuota!
	
    perform *
    from    Esemplare E2
    where   E2.gabbia = new.id;
	
	if not found then
		return NEW;
	end if;
	 	raise exception 'Record non valido; viola il vincolo di genere! ... ';
	end;
end;
$$ language plpgsql;


create or replace function aggiunta_modifica_visita() -- checks n° 4
returns trigger
as
$$
begin

    -- LOGICA FUNZIONE

end;
$$;


create or replace function modifica_genere_abitazione() -- checks n° 5
returns trigger
as
$$
begin

    -- LOGICA FUNZIONE
    -- logica-> caso 1: if nuovo genere = vecchio genere -> lascia modificare anche se non ha senso
    --          caso 2: se ci sono gabbie nell'abitazione -> non puoi modificare!

end;
$$ language plpgsql;


