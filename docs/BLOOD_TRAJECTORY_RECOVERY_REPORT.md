# Trajectory / live wound recovery — 2026-09-26

**Curva abrupta:** `BloodFluidModel.assist_descent` ativava35m/s² inteiros ao cruzar−0,15m/s, anulava a frenagem vertical do arrasto e prendia a velocidade no alvo. A velocidade não teleportava no ápice, mas a aceleração mudava de aproximadamente−9,78 para−44,73m/s² em um substep: causa concreta da mudança brusca de curvatura.

**Pescoço fantasma:** `DummyTarget._die` e o caminho letal de `Weapon` entregavam feridas a `add_remnant` com uma posição mundial. `Wound.detach` congelava X/Z, e `Wound.fall` apenas abaixava Y. O cadáver real era deslocado/rotacionado no nó `Visual`, independente da raiz parada. O emissor continuava depois de o visual ser ocultado. Feridas vivas também usavam a raiz, ignorando sua inclinação visual.

## Pesquisa e histórico recuperados

Lidos `BLOOD_PHYSICS_RESEARCH.md`, auditoria de continuidade, pesquisa Rain e relatório/handoff Fall Speed. Modelo original: densidade1055kg/m³, viscosidade.0048Pa·s, tensão.060N/m; ar1.204kg/m³ e1.81e−5Pa·s. Massa física equivalenteρπd³/6, arrasto Schiller–Naumann dependente de Reynolds/diâmetro; massa representada não determina inércia. Nenhuma constante material ou distribuição de diâmetro foi alterada. Não é validação forense.

`4611c0a` contém a base física; `12d862b` precede esse checkpoint. Os passes posteriores estavam sem commit. A regressão de queda corresponde exatamente ao helper acrescentado no último pass, preservado no snapshot local `validation/blood_trajectory_recovery/baseline/`. Não existe um commit intermediário que possa ser honestamente atribuído a cada ajuste.

## Força nova / ordem real

Com y=velocidade vertical ANTES do substep aerodinâmico, u=−y:

```
w = 1 − smoothstep(−3.0, +0.5, y)
drive = w × [1 − smoothstep(0.8 × target, cap, u)]
brake = smoothstep(cap, cap + 2, u)
v.y += −35 × (drive − brake) × dt
```

Não existe booleano de queda, disparo de ápice, reposição de velocidade ou clamp de velocidade. O limite é uma frenagem suave, não um teto instantâneo. `target/cap` SMALL7/9, MEDIUM9.5/11, LARGE11/13, GLOB12/14m/s agora definem regiões de redução da força; não velocidades idênticas obrigatórias. O arrasto continua atuando integralmente, preservando diferenças por tamanho. MICRO/FINE não recebem assistência; ligamentos usam a categoria de diâmetro. A contribuição é nula acima de+0,5m/s e começa pequena perto do ápice. F11 continua alternando assistência para diagnóstico.

Ordem auditada: contato real/contexto → retirada do reservatório → snapshot de lançamento/padrão da arma → fila primária de três passos → admissão física → por substep: arrasto implícito, gravidade comum, força arcade contínua, posição → raycast varrido → colisão/deposição OU atualização dos arrays → breakup limitado → streak orientado pela velocidade atual. A fila primária representa a retirada imediata já ocorrida; não é uma ferida persistente. Releases residuais são resolvidos e consumidos sincronamente no transform atual. Nenhuma geometria visual independente conduz a colisão.

## Continuidade e velocidade medidas

Fixture determinístico SMALL/MEDIUM/LARGE/GLOB × subida/frente, horizontal, descida, arco alto e arco raso. Substep1/120s; original e corrigido registrados com posição, velocidade, aceleração e ângulo. MEDIUM, lançamento(5,14,0)m/s, janela de nove passos em torno do ápice:

| | T−4 | T−3 | T−2 | T−1 | T | T+1 | T+2 | T+3 | T+4 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Peso novo |.004|.011|.021|.035|.052|.074|.100|.131|.169|
| Y novo m/s |.283|.197|.108|.015|−.082|−.184|−.294|−.413|−.542|
| Aceleração Y m/s² |−10.18|−10.37|−10.67|−11.09|−11.65|−12.34|−13.19|−14.22|−15.46|

Altura do ápice MEDIUM3.820659→3.820345m; diferença0.31mm. LARGE/GLOB também variaram menos de0.4mm nessa amostra. Lançamentos e fração de arcos altos intactos. Aos300ms após ápice: MEDIUM9.168m/s(33.00km/h), LARGE10.122(36.44), GLOB10.384(37.38). Valores do **modelo**, não uma coorte inventada do jogo.

THE_BOX nativo, granada real, medianas dos representantes descendentes presentes em cada instante (não a mesma coorte):

| Tempo após evento | MEDIUM m/s (km/h) | LARGE m/s (km/h) | GLOB m/s (km/h) |
|---|---|---|---|
|.167s|9.569(34.45), N40|11.117(40.02), N55|12.724(45.81), N4|
|.517s|8.901(32.04), N17|sem amostra|sem amostra|
|1.017s|9.660(34.78), N15|10.729(38.62), N2|sem amostra|

Amostras recém-saídas do ápice naturalmente começam mais lentas: em.267s a mediana MEDIUM sobrevivente foi2.419m/s; não foi ocultada nem confundida com a população que já aterrissou. O fixture verifica que essa transição acelera, em vez de permanecer lenta.

Queda controlada MEDIUM do repouso, piso real:0.5/1/2/4m em0.200/0.283/0.383/0.583s. Pass anterior com força abrupta:0.167/0.233/0.333/0.550s. Física sem assistência:0.333/0.483/0.700/1.050s. Suavizar custa algumas dezenas de milissegundos, sem retornar à queda de quase um segundo em2m.

## Origem e ciclo de vida

`BloodReservoir.open_wound` usa o hit exato e armazena sua coordenada local no `blood_source()` da vítima. No dummy esse nó é `Visual`; corpos genéricos usam o próprio Node3D. Feridas guardam somente IDs da fonte/reservatório e geração de respawn. Cada futura emissão verifica instância, árvore, visibilidade, exclusão pendente e geração. Corpo oculto/destruído encerra a ferida; reserva pós-morte remanescente vai ao estoque retido, sem inventar depósito no chão.

Already released: arrays mundiais de posição/velocidade não são consultados nem modificados pelo rastreamento da vítima. O fixture moveu/rotacionou a fonte após105 emissões e confirmou sua independência. Hit(0.12,1.6,−15) → ferida atual(2.642,1.564,−14) → corpo arremessado(3.441,1.571,−14.223). Nova gota nasceu perto da fonte atual. Ocultar o cadáver deixou zero emissores. Respawn e nó liberado foram rejeitados; reservatório sobrevivente cujo dono foi removido também é retirado do registro.

Maul e granada foram disparados pelo WeaponRack real em THE_BOX, assim como Hand Cannon e Daggers. Testes técnicos passaram; combinações exaustivas de ângulos/headshots/esquerda-direita e julgamento perceptual continuam no checklist humano abaixo.

## Preservação / performance

Emissão primária de granada1/2/4 vítimas:222/320/364, sem alteração de amostragem. Pico nativo329/467/514; breakup e tempo de permanência respondem à trajetória. Streaks, largura, seleção, visibilidade, shaders, paleta, áudio e dados de lançamento permaneceram byte a byte iguais ao início deste pass. Superfícies continuam recebendo contato/velocidade reais. Bloom/puddles/fade/runoff não foram editados; fixtures de suporte, crescimento, drenagem, runoff e conservação passaram.

| Vítimas | CPU física média/P95/pico ms | Frame média/P95/pico ms | Queries totais | Writes superfície / totais |
|---|---|---|---:|---:|
|1|1.814/6.566/8.597|16.863/20.390/30.049|27200|620/35378|
|2|2.667/8.528/15.417|17.366/25.351/31.138|33224|762/44617|
|4|2.286/11.948/19.078|18.607/33.150/51.003|34687|1376/38354|

190frames por caso, sem PNG readback nos casos de performance; capturas separadas. P95 nearest-rank. Pass anterior1 vítima: CPU1.923/7.973/13.505ms. Não é comparação pareada: duração/instrumentação/eventos diferem; não se declara ganho garantido. Não há baseline imediato pareado1/2/4 deste pass, apenas medição atual e registros anteriores. Pico51ms ainda é limitação, não promessa de ausência de hitch.

## Memória / estabilidade

Sem novos Nodes de produção, recursos de render/audio, buffers por gota ou resize de MultiMesh. Dois IDs inteiros extras por ferida; referências resolvidas são locais e não retêm o corpo. Registro agora limitado a256reservatórios, quatro feridas por reservatório na configuração atual, quatro fontes pós-morte. Pico observado4fontes, zero ao final,10limpezas nativas. Remoção de entradas inválidas/expiradas e geração impedem fontes antigas. Capacidade física1720, streak192, superfícies3200, wet patches1024 e runoff24 preservadas. Sem mudanças de teardown, slots ou grids de superfície.

Modelo, fixture headless THE_BOX, regressão e teste de fonte órfã concluídos. Houve erros de montagem/parse em dois wrappers de teste, corrigidos e logs preservados. Uma execução gráfica Compatibility terminou com código0; nenhum access violation observado. O último reforço de remoção de reservatório órfão foi validado por teste headless específico depois dela; não houve segundo lançamento gráfico. **O histórico0xC0000005 permanece sem causa resolvida.** Avisos preexistentes de certificados e foley ausente preservados; áudio não foi retunado.

Dados compactos versionados: [summary.json](validation/blood_trajectory_recovery/summary.json). Dados completos/logs/capturas permanecem locais, fora dos commits. Esta validação não constitui aprovação visual.

## Playtest final

Abrir THE_BOX, velocidade normal e câmera em movimento:

1. Hand Cannon: torso/cabeça e ângulos diferentes; origem do hit e evolução suave.
2. Daggers: esquerda/direita e cast-off; gotas livres seguem seu movimento atual.
3. Maul: deslocar/matar vítima; novas gotas seguem corpo, sem fonte no lugar antigo.
4. Granada:1/2/4vítimas, arcos altos → ápice curvo → descida rápida; preservar riqueza/streaks.
5. Verificar manchas exatamente no contato, puddles/fade/runoff iguais; nenhum emissor após ocultar o corpo.

**A aprovação final de curva suave + queda rápida é do jogador em THE_BOX.**

## Git

Base Blood preexistente preservada separadamente em `77f6b92`. O commit seguinte contém a correção atual, fixtures e este relatório. Capturas, vídeos, caches e resultados anteriores modificados não foram incluídos. Main/origin: https://github.com/surdodeumlado/blood.git. Hash final e resultado do push registrados no handoff local e na resposta final.
