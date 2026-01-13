-- Bibliotecas e Pacotes padrão
library IEEE;
use IEEE.std_logic_1164.all;

ENTITY processador IS
    generic(
        e    :    integer    := 2; -- Bits de endereçamento dos registradores (2^2 = 4 regs)
        n    :    integer    := 8  -- Largura de dados e endereços (8 bits)
    );
    
    port(
        -- Entradas de controle global
        clk_v, rst_v    :    in     std_logic;
        
        -- Sinais de monitoramento para Simulação (Waveform)
        pc_saida_v      :    out    std_logic_vector(n-1 downto 0);
        instrucao_v     :    out    std_logic_vector(n-1 downto 0);
        reg1_v, reg2_v  :    out    std_logic_vector(n-1 downto 0);
        imed_3x8        :    out    std_logic_vector(n-1 downto 0);
        result_ula      :    out    std_logic_vector(n-1 downto 0);
        leitura_mem     :    out    std_logic_vector(n-1 downto 0);
        zero_v          :    out    std_logic;
        jump_v          :    out    std_logic;
        branch_v        :    out    std_logic;
        memWrite_v      :    out    std_logic;
        memRead_v       :    out    std_logic;
        ulaop_v         :    out    std_logic;
        imed_5x8        :    out    std_logic_vector(n-1 downto 0)
    );
END ENTITY processador;

ARCHITECTURE behavioral OF processador IS
    -- Sinais internos de sincronismo
    signal clk, rst    :    std_logic;
    
    -- Barramento do Program Counter (PC)
    signal pc_entrada   :    std_logic_vector(n-1 downto 0);
    signal pc_saida     :    std_logic_vector(n-1 downto 0);
    
    -- Saída do somador incremental (PC + 1)
    signal instruc_pc1  :    std_logic_vector(n-1 downto 0);    
    
    -- Barramento da instrução atual (vinda da ROM)
    signal instrucao    :    std_logic_vector(n-1 downto 0);
    
    -- Sinais de decodificação da instrução (Fatiamento)
    signal opcode       :    std_logic_vector(2 downto 0);
    signal reg1         :    std_logic_vector(1 downto 0);
    signal reg2         :    std_logic_vector(1 downto 0);
    signal immed        :    std_logic_vector(2 downto 0);
    signal immedJ       :    std_logic_vector(4 downto 0);
    
    -- Sinais de controle gerados pela UC
    signal Jump         :    std_logic;
    signal Branch       :    std_logic;
    signal Memread      :    std_logic;
    signal Memtoreg     :    std_logic;
    signal ulaOp        :    std_logic;
    signal MemWrite     :    std_logic;
    signal ulaSrc       :    std_logic;
    signal RegWrite     :    std_logic;
    
    -- Interface do Banco de Registradores
    signal escr_dado    :    std_logic_vector(n-1 downto 0);
    signal reg1_saida   :    std_logic_vector(n-1 downto 0);
    signal reg2_saida   :    std_logic_vector(n-1 downto 0);
    
    -- Interface da Unidade Lógica e Aritmética (ULA)
    signal result       :    std_logic_vector(n-1 downto 0);
    signal zero         :    std_logic;
    
    -- Sinais para extensões de sinal (Imediatos)
    signal immed_extd   :    std_logic_vector(n-1 downto 0);
    signal immedJ_extd  :    std_logic_vector(n-1 downto 0);
    
    -- Saídas de Multiplexadores (Seleção de barramento)
    signal mux_ulaout   :    std_logic_vector(n-1 downto 0);
    signal mux_reg      :    std_logic_vector(n-1 downto 0);
    signal instruc_1    :    std_logic_vector(n-1 downto 0); -- Seleção entre PC+1 ou Branch
    
    -- Interface da Memória de Dados (RAM)
    signal dado_out     :    std_logic_vector(n-1 downto 0);
    
    -- Sinais para cálculo de desvios (Branch/Jump)
    signal ender_beq    :    std_logic_vector(n-1 downto 0); -- Alvo do Branch (PC+1 + Offset)
    signal dvc          :    std_logic;                      -- Flag final de desvio condicional
    
BEGIN
        
    -- Mapeamento das portas de entrada para sinais internos
    clk             <= clk_v;
    rst             <= rst_v;
    
    -- Atribuição dos sinais internos para as portas de saída de monitoramento
    pc_saida_v      <= pc_saida;
    instrucao_v     <= instrucao;
    reg1_v          <= reg1_saida;
    reg2_v          <= reg2_saida;
    imed_3x8        <= immed_extd;
    result_ula      <= result;
    leitura_mem     <= dado_out;
    zero_v          <= zero;
    jump_v          <= Jump;
    branch_v        <= Branch;
    memWrite_v      <= MemWrite;
    memRead_v       <= Memread;
    ulaop_v         <= ulaOp;
    imed_5x8        <= immedJ_extd;
    
    -- Estágio 1: Busca (Fetch) e Atualização do PC
    pc          : entity work.pc generic map(n) port map(pc_entrada, clk, rst, pc_saida);
    sum_com1    : entity work.somador generic map(n) port map(pc_saida, "00000001", instruc_pc1);
    mem_inst    : entity work.memoria_instrucao generic map(n) port map(pc_saida, instrucao);
    
    -- Estágio 2: Decodificação (Decode) das instruções
    opcode      <= instrucao(7 downto 5);
    reg1        <= instrucao(4 downto 3);
    
    -- Lógica para definir endereço do segundo registrador (Exceção para LW)
    reg2        <= "00" when opcode = "100" else instrucao(2 downto 1);
    
    -- Extração de imediatos (Campos de 3 bits e 5 bits)
    immed       <= instrucao(2 downto 0);
    immedJ      <= instrucao(4 downto 0);
    
    -- Unidade de Controle: Gerador de sinais de controle via Opcode
    uc          : entity work.unidade_controle port map(opcode, Jump, Branch, Memread, Memtoreg, ulaOp, MemWrite, ulaSrc, RegWrite);    
    
    -- Estágio 3: Banco de Registradores
    banco_reg   : entity work.banco_de_registradores generic map(n, e) port map(clk, RegWrite, reg1, reg2, escr_dado, reg1_saida, reg2_saida);
    
    -- Estágio 4: Execução (Execute) na ULA
    ula         : entity work.ula generic map(n) port map(reg1_saida, mux_ulaout, ulaOp, result, zero);    
    
    -- Extensão de sinal: Converte imediato de 3 bits para 8 bits
    extd1       : entity work.extensor_3x8 port map(immed, immed_extd);
    
    -- Multiplexador da ULA: Escolhe entre Dado do Reg2 ou Valor Imediato
    mux_ula     : entity work.mux_2x1 generic map(n) port map(reg2_saida, immed_extd, ulaSrc, mux_ulaout);
    
    -- Estágio 5: Acesso à Memória de Dados (Memory)
    mem_dado    : entity work.memoria_dados generic map(n) port map(result, reg1_saida, dado_out, MemWrite, Memread, clk);
    
    -- Estágio 6: Escrita de volta (Write-Back) no Banco de Registradores
    escr_dado   <= mux_reg;
    mux_reslt   : entity work.mux_2x1 generic map(n) port map(result, dado_out, Memtoreg, mux_reg);
    
    -- Lógica de Controle de Fluxo (Desvios)
    -- Calcula o endereço de destino caso haja um Branch
    sum_inst    : entity work.somador generic map(n) port map(instruc_pc1, immed_extd, ender_beq);
    
    -- Decisão do Desvio Condicional: Ativado se (Branch = 1 AND Zero = 1)
    dvc         <= Branch and zero;
    
    -- Mux de Desvio Condicional: Seleciona entre Sequencial (PC+1) ou Alvo do Branch
    mux_dvc     : entity work.mux_2x1 generic map(n) port map(instruc_pc1, ender_beq, dvc, instruc_1);
    
    -- Extensão de sinal: Converte endereço de Jump (5 bits) para 8 bits
    extd2       : entity work.extensor_5x8 port map(immedJ, immedJ_extd);
    
    -- Mux de Jump: Seleciona entre o fluxo normal/branch ou um Salto Direto (Jump)
    mux_jump    : entity work.mux_2x1 generic map(n) port map(instruc_1, immedJ_extd, Jump, pc_entrada);
    
END ARCHITECTURE behavioral;