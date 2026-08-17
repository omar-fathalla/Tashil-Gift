---
name: agent-engineering-framework
description: A mandatory 5-stage framework (Prompt, Context, Harness, Loop, Graph) that the agent must follow before writing code or executing complex tasks.
version: 1.0.0
---

# Agent Engineering Framework

**CRITICAL INSTRUCTION:** 
Whenever the user asks you to perform a task in this project, you **MUST NOT** jump directly to writing code or modifying files. Instead, you must strictly follow these **5 Agent Engineering Stages** in order. 

You should document your thought process and decisions for each stage either in your internal thought process, or by creating a temporary plan artifact (e.g., `scratch/engineering_plan.md`) to structure your work.

## Stage 1: Prompt Engineering (Persona & Task Definition)
- **Objective:** Define your role, the exact goals, and the required outputs.
- **Action:** 
  - Clarify any ambiguity in the user's request.
  - Break down the ultimate goal into clear, measurable success criteria.
  - Define the persona you need to adopt (e.g., Senior Security Engineer, UI/UX Expert).

## Stage 2: Context Engineering (Information Gathering)
- **Objective:** Gather all necessary context, filter out noise, and establish the current state.
- **Action:** 
  - Use read tools (`view_file`, `list_dir`, `grep_search`) to understand the current codebase.
  - Do NOT guess the architecture; verify it.
  - Document the key constraints, existing patterns, and dependencies that will affect the task.

## Stage 3: Harness Engineering (Tools & Environment Setup)
- **Objective:** Prepare your tools, sandbox, and execution environment.
- **Action:** 
  - Identify which specific skills, CLI commands, or MCP tools you will need to execute the task.
  - If a specific testing environment or configuration is needed, plan how to set it up.
  - Ensure you understand the constraints of the tools you plan to use.

## Stage 4: Loop Engineering (Feedback & Evaluation)
- **Objective:** Establish a self-correction and evaluation cycle.
- **Action:** 
  - Define exactly how you will verify your work (e.g., running specific tests, compiling the code, checking a URL).
  - Determine your fallback strategy: if the verification fails, what will you check next?
  - Set a limit: decide when you will stop looping and ask the user for clarification to prevent endless loops.

## Stage 5: Graph Engineering (Workflow & Delegation)
- **Objective:** Design the execution workflow and task delegation.
- **Action:** 
  - Break down the task into a step-by-step sequential plan (Graph).
  - Decide if the task requires specialized subagents. If so, plan the prompts you will use with `invoke_subagent` and how you will orchestrate them.
  - Finalize the state transitions of your workflow.

---

**Execution:**
Only after you have consciously passed through these 5 stages are you allowed to begin the actual execution (writing code, creating files, running modifying commands). If the task is massive, present your 5-stage engineering plan to the user for approval first.
