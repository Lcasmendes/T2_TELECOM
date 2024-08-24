import GetPut::*;
import Connectable::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import Assert::*;
import ThreeLevelIO::*;

interface HDB3Decoder;
    interface Put#(Symbol) in;
    interface Get#(Bit#(1)) out;
endinterface

typedef enum {
    IDLE_OR_S1,
    S2,
    S3,
    S4
} State deriving (Bits, Eq, FShow);

module mkHDB3Decoder(HDB3Decoder);
    // Estado e FIFOs
    Vector#(4, FIFOF#(Symbol)) fifos <- replicateM(mkPipelineFIFOF);
    Reg#(Bool) last_pulse_p <- mkReg(False);
    Reg#(State) state <- mkReg(IDLE_OR_S1);

    // Conexões entre os FIFOs
    for (Integer i = 0; i < 3; i = i + 1)
        mkConnection(toGet(fifos[i+1]), toPut(fifos[i]));

    interface in = toPut(fifos[3]);

    interface Get out;
        method ActionValue#(Bit#(1)) get;
            let recent_symbols = tuple4(fifos[0].first, fifos[1].first, fifos[2].first, fifos[3].first);
            let value = 0;

            case (state)
                IDLE_OR_S1:
                    // Se o primeiro símbolo for P ou N, significa 1 binário
                    if (tpl_1(recent_symbols) == P || tpl_1(recent_symbols) == N) action
                        value = 1;
                        last_pulse_p <= (tpl_1(recent_symbols) == P);  // Armazena o pulso mais recente
                    endaction else
                    // Se for Z, significa 0 binário
                    if (tpl_1(recent_symbols) == Z) action
                        value = 0;
                        state <= S2;
                    endaction
                S2:
                    action
                        dynamicAssert(tpl_1(recent_symbols) == Z, "unexpected value on S2");
                        value = 0;
                        state <= S3;
                    endaction
                S3:
                    action
                        dynamicAssert(tpl_1(recent_symbols) == Z, "unexpected value on S3");
                        value = 0;
                        state <= S4;
                    endaction
                S4:
                    action
                        // A quarta posição pode ser P ou N, indicando uma violação ou correção de polaridade
                        if (tpl_1(recent_symbols) == (last_pulse_p ? N : P)) action
                            value = 0;  // Sequência ZZZP ou ZZZN → deve virar 0000
                        endaction else
                            value = 0;  // Sequência PZZP ou NZZN → também vira 0000
                        state <= IDLE_OR_S1;
                    endaction
            endcase

            $display("HDB3Decoder: recent_symbols = ", fshow(recent_symbols),
                ", value = ", fshow(value),
                ", last_pulse_p = ", last_pulse_p,
                ", state = ", fshow(state));

            fifos[0].deq;
            return value;
        endmethod
    endinterface
endmodule
