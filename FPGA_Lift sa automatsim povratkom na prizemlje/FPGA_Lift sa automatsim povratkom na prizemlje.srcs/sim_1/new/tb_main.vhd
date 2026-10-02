----------------------------------------------------------------------------------
-- FPGA Design Challenge 2026 - Tim T5
-- Testbench za main.vhd (Zadatak 5: lift sa automatskim povratkom)
--
-- Simulacija koristi CLK_FREQ = 10, tj. "1 sekunda" = 10 taktova = 100 ns,
-- pa ceo scenario traje ~17.2 us simulacionog vremena. U waveform-u:
--     1 s realnog vremena  <->  100 ns simulacije
--
-- Testovi (samoproveravajuci - assert + brojac gresaka):
--   T1  Reset: sprat 0, vrata zatvorena, nema zahteva
--   T2  Spoljasnji poziv sa sprata 2: LED poziva, 5 s po spratu, vrata 10 s
--   T3  ZADATAK 5: posle 30 s neaktivnosti lift se vraca na sprat 0
--       i drzi vrata otvorena do novog zahteva
--   T4  Unutrasnji zahtev (putnik u kabini) zatvara vrata i vozi na sprat 1
--   T5  Prioritet unutrasnjih zahteva nad spoljasnjim
--   T6  Reset tokom rada: zahtevi obrisani, lift se vraca na 0 sa zatvorenim vratima
--
-- Vivado: postaviti tb_main kao top simulacije i pokrenuti "run all".
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity tb_main is
end tb_main;

architecture sim of tb_main is

    constant CLK_FREQ_SIM : integer := 10;
    constant CLK_PERIOD   : time    := 10 ns;
    constant SEK          : time    := CLK_FREQ_SIM * CLK_PERIOD;  -- "1 sekunda"
    constant TOL          : time    := SEK / 5;                    -- tolerancija 0.2 s

    -- Kodovi izlaza
    constant RGB_OTV   : std_logic_vector(2 downto 0) := "100";  -- crvena
    constant RGB_ZATV  : std_logic_vector(2 downto 0) := "010";  -- zelena
    constant RGB_POKR  : std_logic_vector(2 downto 0) := "001";  -- plava
    constant SEG_0     : std_logic_vector(6 downto 0) := "0111111";
    constant SEG_1     : std_logic_vector(6 downto 0) := "0000110";
    constant SEG_2     : std_logic_vector(6 downto 0) := "1011011";

    signal clk        : std_logic := '0';
    signal rst        : std_logic := '0';
    signal taster_in  : std_logic_vector(2 downto 0) := "000";
    signal taster_out : std_logic_vector(2 downto 0) := "000";
    signal senzor     : std_logic := '0';
    signal seg7       : std_logic_vector(6 downto 0);
    signal RGB        : std_logic_vector(2 downto 0);
    signal led_sprat  : std_logic_vector(2 downto 0);

    signal kraj       : boolean := false;

    -- Pomocni signal za waveform: sprat dekodovan sa displeja
    signal sprat_prikaz : integer range -1 to 2;

    -- Vreme u "sekundama" (za ispis)
    function u_sek(t : time) return string is
    begin
        return integer'image(t / (SEK / 100) / 100) & "." &
               integer'image((t / (SEK / 100)) mod 100 / 10) & " s";
    end function;

begin

    -- Generator takta (zaustavlja se na kraju da bi se "run all" zavrsio)
    clk <= not clk after CLK_PERIOD / 2 when not kraj else '0';

    sprat_prikaz <= 0 when seg7 = SEG_0 else
                    1 when seg7 = SEG_1 else
                    2 when seg7 = SEG_2 else -1;

    dut : entity work.main
        generic map ( CLK_FREQ => CLK_FREQ_SIM )
        port map (
            clk        => clk,
            rst        => rst,
            taster_in  => taster_in,
            taster_out => taster_out,
            senzor     => senzor,
            seg7       => seg7,
            RGB        => RGB,
            led_sprat  => led_sprat
        );

    stim : process
        variable greske : integer := 0;
        variable t0, t1 : time;

        -- Provera uslova
        procedure proveri(uslov : boolean; poruka : string) is
        begin
            if uslov then
                report "  OK:    " & poruka severity note;
            else
                report "  GRESKA: " & poruka severity error;
                greske := greske + 1;
            end if;
        end procedure;

        -- Provera trajanja sa tolerancijom
        procedure proveri_vreme(d, ocekivano : time; poruka : string) is
        begin
            proveri(d >= ocekivano - TOL and d <= ocekivano + TOL,
                    poruka & " = " & u_sek(d) & " (ocekivano " & u_sek(ocekivano) & ")");
        end procedure;

        -- Kratak pritisak tastera (nekoliko taktova)
        procedure pritisni_out(t : std_logic_vector(2 downto 0)) is
        begin
            taster_out <= t;  wait for 5 * CLK_PERIOD;  taster_out <= "000";
        end procedure;

        procedure pritisni_in(t : std_logic_vector(2 downto 0)) is
        begin
            taster_in <= t;   wait for 5 * CLK_PERIOD;  taster_in <= "000";
        end procedure;

        -- Cekanje na izlaz; ako je uslov vec ispunjen, ne ceka
        -- (izbegava propustanje dogadjaja koji se desio tokom pritiska tastera)
        procedure cekaj_rgb(v : std_logic_vector(2 downto 0); tmax : time) is
        begin
            if RGB /= v then wait until RGB = v for tmax; end if;
        end procedure;

        procedure cekaj_sprat(n : integer; tmax : time) is
        begin
            if sprat_prikaz /= n then wait until sprat_prikaz = n for tmax; end if;
        end procedure;

    begin
        ------------------------------------------------------------------------
        report "===== T1: Reset =====";
        rst <= '1';
        wait for 2 * SEK;
        rst <= '0';
        wait for 2 * SEK;
        proveri(sprat_prikaz = 0,  "lift na spratu 0");
        proveri(RGB = RGB_ZATV,    "vrata zatvorena (zelena)");
        proveri(led_sprat = "000", "nema aktivnih spoljasnjih poziva");

        ------------------------------------------------------------------------
        report "===== T2: Spoljasnji poziv sa sprata 2 =====";
        pritisni_out("100");
        wait for 3 * CLK_PERIOD;
        proveri(led_sprat = "100", "LED poziva na spratu 2 svetli");

        cekaj_rgb(RGB_POKR, 2 * SEK);
        proveri(RGB = RGB_POKR, "lift krenuo (plava)");
        t0 := now;

        cekaj_sprat(1, 7 * SEK);
        proveri_vreme(now - t0, 5 * SEK, "sprat 0 -> 1");
        t1 := now;

        cekaj_sprat(2, 7 * SEK);
        proveri_vreme(now - t1, 5 * SEK, "sprat 1 -> 2");

        cekaj_rgb(RGB_OTV, 2 * SEK);
        proveri(RGB = RGB_OTV, "vrata otvorena na spratu 2 (crvena)");
        t0 := now;
        wait for 5 * CLK_PERIOD;
        proveri(led_sprat = "000", "poziv obrisan nakon opsluzivanja");

        wait until RGB /= RGB_OTV for 12 * SEK;
        proveri_vreme(now - t0, 10 * SEK, "vrata otvorena");
        t0 := now;   -- pocetak zatvaranja vrata

        ------------------------------------------------------------------------
        report "===== T3: ZADATAK 5 - automatski povratak posle 30 s =====";
        -- Zatvaranje traje 2 s, zatim lift miruje (POCETNO).
        -- Povratak mora da krene tacno 30 s nakon ulaska u mirovanje.
        wait for 2 * SEK + 29 * SEK;
        proveri(RGB = RGB_ZATV and sprat_prikaz = 2,
                "lift jos miruje na spratu 2 posle 29 s neaktivnosti");

        cekaj_rgb(RGB_POKR, 3 * SEK);
        proveri_vreme(now - t0 - 2 * SEK, 30 * SEK, "vreme neaktivnosti do povratka");
        t1 := now;

        cekaj_sprat(0, 12 * SEK);
        proveri_vreme(now - t1, 10 * SEK, "povratak sprat 2 -> 0");

        cekaj_rgb(RGB_OTV, 2 * SEK);
        proveri(RGB = RGB_OTV, "vrata otvorena u prizemlju nakon povratka");

        wait for 20 * SEK;
        proveri(RGB = RGB_OTV and sprat_prikaz = 0,
                "vrata i dalje otvorena posle 20 s (cekaju novi zahtev)");

        ------------------------------------------------------------------------
        report "===== T4: Unutrasnji zahtev za sprat 1 =====";
        senzor <= '1';                      -- putnik u kabini
        wait for 5 * CLK_PERIOD;
        pritisni_in("010");

        cekaj_rgb(RGB_ZATV, 2 * SEK);
        proveri(RGB = RGB_ZATV, "novi zahtev zatvara vrata");
        t0 := now - RGB'last_event;     -- trenutak kada je zatvaranje pocelo
        cekaj_rgb(RGB_POKR, 3 * SEK);
        proveri_vreme(now - t0, 2 * SEK, "zatvaranje vrata");

        cekaj_rgb(RGB_OTV, 7 * SEK);
        proveri(sprat_prikaz = 1 and RGB = RGB_OTV, "vrata otvorena na spratu 1");

        ------------------------------------------------------------------------
        report "===== T5: Prioritet unutrasnjih zahteva =====";
        -- Dok su vrata otvorena na spratu 1: spoljasnji poziv sa 0,
        -- a putnik u kabini bira sprat 2. Lift mora prvo gore.
        wait for 2 * SEK;
        pritisni_out("001");
        pritisni_in("100");
        wait for 3 * CLK_PERIOD;
        proveri(led_sprat = "001", "LED spoljasnjeg poziva sa sprata 0 svetli");

        cekaj_rgb(RGB_POKR, 12 * SEK);
        wait until sprat_prikaz /= 1 for 7 * SEK;
        proveri(sprat_prikaz = 2, "lift prvo opsluzuje unutrasnji zahtev (sprat 2)");

        cekaj_rgb(RGB_OTV, 2 * SEK);
        senzor <= '0';                      -- putnik izasao
        proveri(led_sprat = "001", "spoljasnji poziv sa sprata 0 i dalje aktivan");

        cekaj_sprat(0, 25 * SEK);
        cekaj_rgb(RGB_OTV, 2 * SEK);
        proveri(sprat_prikaz = 0 and RGB = RGB_OTV, "zatim opsluzen poziv sa sprata 0");
        wait for 5 * CLK_PERIOD;
        proveri(led_sprat = "000", "poziv sa sprata 0 obrisan");

        ------------------------------------------------------------------------
        report "===== T6: Reset tokom rada =====";
        cekaj_rgb(RGB_ZATV, 12 * SEK);
        pritisni_out("100");               -- poziv sa sprata 2
        cekaj_sprat(2, 15 * SEK);
        cekaj_rgb(RGB_OTV, 2 * SEK);
        pritisni_out("001");               -- jos jedan poziv, treba da ga reset obrise
        wait for 2 * SEK;

        rst <= '1';
        wait for 3 * CLK_PERIOD;
        proveri(led_sprat = "000", "reset brise sve zahteve");
        proveri(RGB = RGB_ZATV,    "reset zatvara vrata");
        wait for SEK;
        rst <= '0';

        cekaj_rgb(RGB_POKR, 3 * SEK);
        proveri(RGB = RGB_POKR, "posle reseta lift krece ka spratu 0");
        cekaj_sprat(0, 12 * SEK);
        wait for 2 * SEK;
        proveri(sprat_prikaz = 0 and RGB = RGB_ZATV,
                "lift na spratu 0, vrata zatvorena");

        ------------------------------------------------------------------------
        report "==========================================";
        if greske = 0 then
            report "SVI TESTOVI SU PROSLI";
        else
            report "BROJ GRESAKA: " & integer'image(greske) severity error;
        end if;
        report "==========================================";

        kraj <= true;
        wait;
    end process;

end sim;