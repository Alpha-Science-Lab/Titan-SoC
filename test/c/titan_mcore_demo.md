# AlphaTitan Multicore Execution Demo

## **Purpose**

This document captures the original execution plan for the AlphaTitan multicore demonstration and is intended to match the intended command flow exactly. The focus is on the behavioral sequence, not on the low-level RTL implementation details.

The design uses four harts:
- Hart 0 = orchestrator / master
- Hart 1 = arithmetic worker
- Hart 2 = special-compute worker
- Hart 3 = I/O processor

---

## **1. Hart dispatch at startup**

At the very beginning, every hart reads its hart id and branches to a hart-specific task.

The dispatch pattern is:
- Hart 0 goes to the orchestrator flow
- Hart 1 goes to the arithmetic worker flow
- Hart 2 goes to the special-compute flow
- Hart 3 goes to the I/O processor flow

This is the first control step and it determines the rest of the software behavior.

---

## **2. Hart 0: master controller flow**

Hart 0 does these:

1. Initialize the required peripherals and interrupt state.
2. Use DMA to replicate TCIM0 content into TCIM1, TCIM2, and TCIM3.
3. Write to the reset controller to release cores 1, 2, and 3 from reset.
4. Write the shared operands into the shared data RAM.
5. Raise the test interrupt to Hart 1 and the test interrupt to Hart 2 to indicate that the operands are ready.
6. Wait for both Hart 1 and Hart 2 to send completion interrupts.
7. After both completion interrupts are received, print a UART message indicating that both worker tasks are complete.
8. Continue polling or waiting for any independent Hart 3 I/O notification; if such an event is reported, print the corresponding UART message.

This is the precise control flow: Hart 0 is the **master controller**. It **posts the work once**, **wakes both worker harts**, **waits for both completion signals**, and separately handles any independent I/O event from Hart 3.

---

## **3. Hart 1 behavior**

Hart 1 does these:

1. Wait for the Hart 0 start interrupt.
2. Read the operands from the shared data RAM.
3. Perform the multiplication operation.
4. Write the multiplication result back to the shared data RAM.
5. Send a completion interrupt back to Hart 0 through the test interrupt mechanism.

Hart 1 is an independent worker. It does not depend on Hart 2 for its own execution, and it is launched concurrently with Hart 2 after Hart 0 has posted the shared operands.

---

## **4. Hart 2 behavior**

Hart 2 does these:

1. Wait for the Hart 0 start interrupt.
2. Read the relevant operands or data from the shared data RAM.
3. Perform the special compute task, such as an integer square-root approximation or another specialized arithmetic routine.
4. Write the result back to the shared data RAM.
5. Send a completion interrupt back to Hart 0 through the test interrupt mechanism.

Hart 2 is a second independent worker and runs concurrently with Hart 1 after Hart 0 has posted the shared work.

---

## **5. Hart 3 behavior**

Hart 3 does these:

1. Act as the I/O processor.
2. Monitor the button inputs for a specific button-press pattern.
3. When the pattern matches, blink the LED for a programmed duration using the timer delay.
4. Send an I/O event interrupt to Hart 0 through the test interrupt mechanism.

This path is independent of the Hart 1/Hart 2 compute path. Hart 3 may trigger an interrupt to Hart 0 at any time if the configured button event occurs, but it does not participate in the Hart 1/Hart 2 completion handshake.

---

## **6. Inter-hart communication**

Inter-hart communication happens through the test interrupt structure.

The mechanism is:

1. The initiating hart writes to the specified indices into the scratchpad register of the test peripheral.
2. The initiating hart raises the target test interrupt by writing the appropriate count into the relevant interrupt register.
3. The receiving hart checks the interrupt and reads the scratchpad indices to determine the event and source.
4. The receiving hart clears the interrupt by writing 0 to the interrupt register on the test peripheral, and also clears or updates the corresponding scratchpad source index for that interrupt.

This is the **fundamental signaling contract** for the demo.

Specific mapping for this design:
- Hart 0 is triggered via **test interrupt 0**.
- Hart 1 is triggered via **test interrupt 1**.
- Hart 2 is triggered via **test interrupt 2**.
- Hart 3 is triggered via **test interrupt 3**.
- Harts can **independently raise interrupts** by writing the proper scratchpad index field and then asserting the target test interrupt.

---

## **7. Interrupt source encoding**

The source of the interrupt is specified by writing metadata into the scratchpad register of the test peripheral before raising the interrupt.

**CRITICAL: scratchpad update rule**

The scratchpad is a 32-bit register and a write replaces the complete word. A bit update must be performed as a **read-modify-write sequence**: first read the current scratchpad value, then update only the targeted bits, and finally write the new value back. This load/store sequence must be serialized with a **spinlock** whenever a hart is modifying shared scratchpad state. Plain scratchpad reads do not need a spinlock unless the read is part of a **read-modify-write update**.

> Never write a **partial scratchpad value** directly. A direct write can **overwrite unrelated interrupt bits** and break the inter-hart signaling contract.

The required encoding convention is:
- scratchpad[31:28] test interrupt 3 source indication bits

    Within each 4-bit field, source indication is one-hot by hart id: for example
    - scratchpad[31] in the interrupt-3 field indicates source Hart 3
    - scratchpad[30] in the interrupt-3 field indicates source Hart 2
    - scratchpad[29] in the interrupt-3 field indicates source Hart 1
    - scratchpad[28] in the interrupt-3 field indicates source Hart 0

- scratchpad[27:24] test interrupt 2 source indication bits
- scratchpad[23:20] test interrupt 1 source indication bits
- scratchpad[19:16] test interrupt 0 source indication bits

The corresponding meaning is:
- the initiating hart writes the source metadata into the scratchpad field associated with the target interrupt before raising the interrupt
- the receiving hart decodes the source from the relevant scratchpad bits and uses the interrupt level as the trigger to service the event
- the interrupt is cleared by writing 0 to the corresponding test-interrupt register after the event has been handled
- when an interrupt is serviced, the corresponding scratchpad source field for that interrupt index must also be updated (typically cleared)
- any scratchpad bit update must be done as a **read-modify-write under a spinlock**; a plain read is sufficient for observation only
- harts can **independently raise interrupts** without waiting for another hart's interrupt to be serviced first

This gives a precise and deterministic inter-hart signaling contract: the **interrupt wakes the target hart**, and the **scratchpad tells it which source** is associated with each interrupt channel.

The corresponding locking pattern is:

```c
while (spinlock_read(SCRATCHPAD_LOCK) != 0) {
}
uint32_t sp = scratchpad_read();
sp |= (1u << SRC_BIT);
scratchpad_write(sp);
spinlock_write(SCRATCHPAD_LOCK, 0);
```

In this pattern, the spinlock serializes the read-modify-write sequence. The lock peripheral uses a read-to-acquire / write-0-to-release convention, so the lock must be held for the entire read-modify-write window and released only after the scratchpad write completes.

---

## **8. Exact execution order: demo flow**

The exact sequence is:

1. All harts start and read mhartid (once out of reset). Initially Hart 1, 2 and 3 are in reset unless brought out of reset by hart 0.
2. Each hart branches to its hart-specific routine.
3. Hart 0 initializes the peripherals and interrupt state.
4. Hart 0 programs DMA to copy TCIM0 contents into TCIM1, TCIM2, and TCIM3.
5. Hart 0 writes to the reset controller to release harts 1, 2, and 3 from reset.
6. Hart 0 writes the shared operands into the shared data RAM.
7. Hart 0 raises the Hart 1 and Hart 2 start interrupts.
8. Hart 1 and Hart 2 begin their independent worker tasks concurrently.
9. Hart 1 reads its operands from the shared data RAM, performs the multiplication, and writes the result back.
10. Hart 2 reads its data from the shared data RAM, performs the special compute, and writes the result back.
11. Hart 1 raises the completion interrupt to Hart 0.
12. Hart 2 raises the completion interrupt to Hart 0.
13. Hart 0 waits for both completion signals and then prints a UART message indicating that both worker tasks are complete.
14. Hart 3 independently monitors the button pattern.
15. If the button pattern matches, Hart 3 blinks the LED and raises an I/O event interrupt to Hart 0.
16. Hart 0 handles that I/O interrupt and prints the corresponding UART message.

This is the precise end-to-end flow of the multicore demo: Hart 0 **posts work to both compute workers**, **waits for both completions**, and Hart 3 runs an independent I/O path that may **interrupt Hart 0 separately**.

---

## **9. Role summary**

- Hart 0: master controller and UART logger
- Hart 1: arithmetic computation worker
- Hart 2: special compute worker
- Hart 3: I/O and LED/button processor

The whole design is intentionally coordinated by interrupt-based handshakes and shared memory.

---

## **10. Implementation intent: C test contract**

The eventual C test should follow the same logic:

- each hart starts from a hart-id-specific entry point
- Hart 0 performs the platform setup and broadcasting of work
- worker harts read operands from shared RAM
- worker harts use the test interrupt mechanism for finish signaling
- Hart 0 waits for completion and prints status messages over UART
- all inter-hart signaling is performed through the test peripheral (interrupt register and scratchpad register)
- interrupt clear is done by writing 0 to the test interrupt register after each event is serviced
- the corresponding scratchpad source field for that interrupt index is also updated/cleared when servicing completes

This document is therefore a specification of the control flow that the C implementation must follow.
