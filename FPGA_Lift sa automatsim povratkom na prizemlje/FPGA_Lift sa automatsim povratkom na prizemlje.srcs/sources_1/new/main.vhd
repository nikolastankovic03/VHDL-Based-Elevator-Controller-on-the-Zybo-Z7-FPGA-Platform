library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity main is
    Generic (
        CLK_FREQ : integer := 100_000_000   
    );
    Port (
        clk            : in  STD_LOGIC;
        rst            : in  STD_LOGIC;
        taster_in      : in  STD_LOGIC_VECTOR (2 downto 0); -- Unutrasnji tasteri (0, 1, 2)
        taster_out     : in  STD_LOGIC_VECTOR (2 downto 0); -- Spoljasnji pozivi (0, 1, 2)
        senzor         : in  STD_LOGIC;                     -- Senzor prisutnosti putnika
        seg7           : out STD_LOGIC_VECTOR (6 downto 0); -- Prikaz sprata
        RGB            : out STD_LOGIC_VECTOR (2 downto 0); -- R(Otv), G(Zatv), B(Pokret)
        led_sprat      : out STD_LOGIC_VECTOR (2 downto 0)  -- Aktivni spoljasnji pozivi po spratovima
    );
end main;

architecture Behavioral of main is

    -- Vremenski parametri (u sekundama)
    constant T_KRETANJE       : integer := 5;   -- izmedju susednih spratova
    constant T_VRATA_OTV      : integer := 10;  -- vrata otvorena
    constant T_VRATA_ZATV     : integer := 2;   -- zatvaranje vrata
    constant T_NEAKTIVNOSTI   : integer := 30;  -- automatski povratak

    type stanje_type is (POCETNO, NA_GORE, NA_DOLE, DOLAZAK, VRATA_OTVORENA, VRATA_ZATVORENA);
    signal stanje, sledece_stanje : stanje_type := POCETNO;

    -- Sinhronizacija asinhronih ulaza (2 flip-flopa)
    signal tin_s1, tin_s2   : std_logic_vector(2 downto 0) := "000";
    signal tout_s1, tout_s2 : std_logic_vector(2 downto 0) := "000";
    signal sen_s1, sen_s2   : std_logic := '0';

    -- Registri zahteva
    signal tr_sprat      : integer range 0 to 2 := 0;
    signal zahtevi_in    : std_logic_vector(2 downto 0) := "000";
    signal zahtevi_out   : std_logic_vector(2 downto 0) := "000";
    signal svi_zahtevi   : std_logic_vector(2 downto 0);

    -- Tajmeri
    signal tick1s              : std_logic := '0';
    signal clk_brojac          : integer range 0 to CLK_FREQ - 1 := 0;
    signal sekunde             : integer range 0 to 15 := 0;
    signal tajmer_neaktivnosti : integer range 0 to T_NEAKTIVNOSTI := 0;

    -- Flagovi povratka na sprat 0
    signal posle_reseta  : std_logic := '0'; -- povratak nakon reseta (vrata ostaju zatvorena)
    signal povratak      : std_logic := '0'; -- Zadatak 5: povratak zbog neaktivnosti

begin

    ------------------------------------------------------------------------------
    -- SINHRONIZACIJA ULAZA
    ------------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            tin_s1  <= taster_in;   tin_s2  <= tin_s1;
            tout_s1 <= taster_out;  tout_s2 <= tout_s1;
            sen_s1  <= senzor;      sen_s2  <= sen_s1;
        end if;
    end process;

    ------------------------------------------------------------------------------
    -- PRIORITET: ako je putnik u kabini i postoji unutrasnji zahtev, opsluzuju se
    -- prvo unutrasnji zahtevi; u suprotnom spoljasnji pozivi.
    ------------------------------------------------------------------------------
    svi_zahtevi <= zahtevi_in when (sen_s2 = '1' and zahtevi_in /= "000") else zahtevi_out;

    ------------------------------------------------------------------------------
    -- REGISTRACIJA ZAHTEVA (brisanje tek nakon opsluzivanja)
    ------------------------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '1' then
            zahtevi_in  <= "000";
            zahtevi_out <= "000";
        elsif rising_edge(clk) then
            zahtevi_in  <= zahtevi_in  or tin_s2;
            zahtevi_out <= zahtevi_out or tout_s2;

            -- Zahtev za trenutni sprat je opsluzen kada su vrata otvorena
            if stanje = VRATA_OTVORENA then
                zahtevi_in(tr_sprat)  <= '0';
                zahtevi_out(tr_sprat) <= '0';
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------------
    -- GENERATOR TAKTA 1 s
    ------------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if clk_brojac = CLK_FREQ - 1 then
                clk_brojac <= 0;
                tick1s     <= '1';
            else
                clk_brojac <= clk_brojac + 1;
                tick1s     <= '0';
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------------
    -- REGISTAR STANJA I TAJMERI
    -- Stanja se menjaju na tick1s; DOLAZAK je samo stanje odluke i napusta se
    -- vec u sledecem taktu, pa ne dodaje 1 s na vreme kretanja.
    ------------------------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '1' then
            stanje              <= POCETNO;
            sekunde             <= 0;
            tajmer_neaktivnosti <= 0;
            povratak            <= '0';
            posle_reseta        <= '1';  -- lift treba da se vrati na sprat 0
        elsif rising_edge(clk) then

            if tr_sprat = 0 then
                posle_reseta <= '0';
            end if;

            if tick1s = '1' or stanje = DOLAZAK then
                -- Promena stanja i brojac sekundi unutar stanja
                if stanje /= sledece_stanje then
                    stanje  <= sledece_stanje;
                    sekunde <= 0;
                elsif tick1s = '1' and sekunde < 15 then
                    sekunde <= sekunde + 1;
                end if;

                -- Zadatak 5: pamti da je pokrenut automatski povratak;
                -- brise se cim stigne novi zahtev
                if stanje = POCETNO and sledece_stanje = NA_DOLE
                   and svi_zahtevi = "000" and posle_reseta = '0' then
                    povratak <= '1';
                elsif svi_zahtevi /= "000" then
                    povratak <= '0';
                end if;
            end if;

            -- Tajmer neaktivnosti: broji samo dok lift miruje bez zahteva
            if tick1s = '1' then
                if stanje /= POCETNO or svi_zahtevi /= "000" then
                    tajmer_neaktivnosti <= 0;
                elsif tajmer_neaktivnosti < T_NEAKTIVNOSTI then
                    tajmer_neaktivnosti <= tajmer_neaktivnosti + 1;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------------
    -- TRENUTNI SPRAT
    -- Namerno bez reseta: reset ne "teleportuje" lift, vec ga FSM vozi na sprat 0.
    ------------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if tick1s = '1' and sekunde >= T_KRETANJE - 1 then
                if stanje = NA_GORE and tr_sprat < 2 then
                    tr_sprat <= tr_sprat + 1;
                elsif stanje = NA_DOLE and tr_sprat > 0 then
                    tr_sprat <= tr_sprat - 1;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------------
    -- KOMBINACIONA LOGIKA FSM
    -- Napomena: prelaz se upisuje na sledeci tick, pa su pragovi (T - 1).
    ------------------------------------------------------------------------------
    process(stanje, svi_zahtevi, tr_sprat, sekunde, tajmer_neaktivnosti, posle_reseta, povratak)
        variable ima_gore, ima_dole : boolean;
    begin
        -- Da li postoji zahtev iznad / ispod trenutnog sprata
        ima_gore := (tr_sprat = 0 and (svi_zahtevi(1) = '1' or svi_zahtevi(2) = '1')) or
                    (tr_sprat = 1 and  svi_zahtevi(2) = '1');
        ima_dole := (tr_sprat = 2 and (svi_zahtevi(1) = '1' or svi_zahtevi(0) = '1')) or
                    (tr_sprat = 1 and  svi_zahtevi(0) = '1');

        sledece_stanje <= stanje;
        RGB <= "000";

        case stanje is
            when POCETNO =>
                RGB <= "010"; -- Zelena: miruje, vrata zatvorena
                if svi_zahtevi(tr_sprat) = '1' then
                    sledece_stanje <= VRATA_OTVORENA;
                elsif ima_gore then
                    sledece_stanje <= NA_GORE;
                elsif ima_dole then
                    sledece_stanje <= NA_DOLE;
                -- Povratak na sprat 0: nakon reseta ili 30 s neaktivnosti (Zadatak 5)
                elsif tr_sprat /= 0 and
                      (posle_reseta = '1' or tajmer_neaktivnosti >= T_NEAKTIVNOSTI - 1) then
                    sledece_stanje <= NA_DOLE;
                end if;

            when NA_GORE =>
                RGB <= "001"; -- Plava: kretanje
                if sekunde >= T_KRETANJE - 1 then
                    sledece_stanje <= DOLAZAK;
                end if;

            when NA_DOLE =>
                RGB <= "001"; -- Plava: kretanje
                if sekunde >= T_KRETANJE - 1 then
                    sledece_stanje <= DOLAZAK;
                end if;

            when DOLAZAK =>
                RGB <= "001";
                if svi_zahtevi(tr_sprat) = '1' or (tr_sprat = 0 and povratak = '1') then
                    sledece_stanje <= VRATA_OTVORENA;
                elsif ima_gore then
                    sledece_stanje <= NA_GORE;
                elsif ima_dole or (tr_sprat /= 0 and (povratak = '1' or posle_reseta = '1')) then
                    sledece_stanje <= NA_DOLE;
                else
                    sledece_stanje <= POCETNO;  -- npr. kraj povratka nakon reseta
                end if;

            when VRATA_OTVORENA =>
                RGB <= "100"; -- Crvena: vrata otvorena
                if tr_sprat = 0 and povratak = '1' then
                    -- Zadatak 5: nakon automatskog povratka vrata ostaju otvorena
                    -- u prizemlju do novog zahteva
                    if svi_zahtevi /= "000" then
                        sledece_stanje <= VRATA_ZATVORENA;
                    end if;
                elsif sekunde >= T_VRATA_OTV - 1 then
                    sledece_stanje <= VRATA_ZATVORENA;
                end if;

            when VRATA_ZATVORENA =>
                RGB <= "010"; -- Zelena: zatvaranje vrata
                if sekunde >= T_VRATA_ZATV - 1 then
                    if svi_zahtevi(tr_sprat) = '1' then
                        sledece_stanje <= VRATA_OTVORENA;  -- poziv sa istog sprata
                    elsif ima_gore then
                        sledece_stanje <= NA_GORE;
                    elsif ima_dole then
                        sledece_stanje <= NA_DOLE;
                    else
                        sledece_stanje <= POCETNO;
                    end if;
                end if;

            when others =>
                sledece_stanje <= POCETNO;
        end case;
    end process;

    ------------------------------------------------------------------------------
    -- IZLAZI
    ------------------------------------------------------------------------------
    led_sprat <= zahtevi_out;   -- LED svetli dok je spoljasnji poziv aktivan

    with tr_sprat select
        seg7 <= "0111111" when 0, -- Cifra 0
                "0000110" when 1, -- Cifra 1
                "1011011" when 2, -- Cifra 2
                "0000000" when others;

end Behavioral;