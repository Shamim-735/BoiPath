import asyncio
import re
import secrets
import time

from fastapi import Depends, HTTPException, Request, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool

CODE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
CODE = re.compile(f"^[{CODE_ALPHABET}]{{8}}$")


class TurnPage(BaseModel):
    page: int = Field(ge=1, le=100000)


class StartSession(TurnPage):
    textbook_id: str = Field(min_length=1, max_length=36)


def session_state(db, code):
    if not CODE.fullmatch(code):
        return None
    with db.connect() as tx:
        row = tx.one("""SELECT code,textbook_id,current_page,revision,expires_at,status
            FROM classrooms WHERE code=?""", (code,))
    if row and row["status"] == "active" and row["expires_at"] <= int(time.time()):
        row["status"] = "expired"
    return row


def install_classrooms(app, db, require_user, throttle, limits, origins):
    prefix = "/api/v1/classrooms"

    def teacher(user=Depends(require_user)):
        if user["role"] != "teacher":
            raise HTTPException(403, "Teacher role required")
        return user

    @app.post(prefix, status_code=201)
    def create(request: Request, data: StartSession, user=Depends(teacher)):
        throttle(request, "start-classroom", 10, 3600)
        expiry = int(time.time()) + 7200
        with db.connect() as tx:
            if not tx.one("SELECT id FROM books WHERE id=? AND verification_status='verified'", (data.textbook_id,)):
                raise HTTPException(404, "Verified textbook required")
            for _attempt in range(5):
                code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(8))
                if tx.run("""INSERT INTO classrooms(code,teacher_id,textbook_id,current_page,expires_at,status)
                    VALUES (?,?,?,?,?,'active') ON CONFLICT DO NOTHING""",
                          (code, user["id"], data.textbook_id, data.page, expiry)).rowcount:
                    return {"code": code, "expires_at": expiry}
        raise HTTPException(503, "Could not assign a session code")

    @app.get(prefix + "/{code}")
    def lookup(request: Request, code: str):
        throttle(request, "lookup-classroom", 45)
        state = session_state(db, code.upper())
        if not state:
            raise HTTPException(404, "Classroom not found")
        return state

    def change(code, user, status, page=None):
        code = code.upper()
        with db.connect() as tx:
            row = tx.one("SELECT teacher_id,status,expires_at FROM classrooms WHERE code=?", (code,))
            if row is None or row["teacher_id"] != user["id"]:
                raise HTTPException(404, "Classroom not found")
            if row["status"] != "active" or row["expires_at"] <= int(time.time()):
                raise HTTPException(409, "Classroom ended or expired")
            result = tx.run("""UPDATE classrooms SET status=?,current_page=COALESCE(?,current_page),revision=revision+1
                WHERE code=? AND teacher_id=? AND status='active' AND expires_at>?""",
                            (status, page, code, user["id"], int(time.time())))
            if not result.rowcount:
                raise HTTPException(409, "Classroom ended or expired")
        return {"status": status}

    @app.patch(prefix + "/{code}/page")
    def page(request: Request, code: str, data: TurnPage, user=Depends(teacher)):
        throttle(request, "classroom-page", 160)
        return change(code, user, "active", data.page)

    @app.post(prefix + "/{code}/end")
    def end(code: str, user=Depends(teacher)):
        return change(code, user, "ended")

    @app.websocket(prefix + "/{code}/ws")
    async def stream(websocket: WebSocket, code: str):
        origin = websocket.headers.get("origin")
        if origin and origin not in origins:
            await websocket.close(1008)
            return
        try:
            limits.check("classroom-socket", websocket.client.host if websocket.client else "unknown", 40, 60)
        except HTTPException:
            await websocket.close(1008)
            return
        code = code.upper()
        state = await run_in_threadpool(session_state, db, code)
        if not state:
            await websocket.close(1008)
            return
        await websocket.accept()
        previous = None
        try:
            while state is not None:
                if state != previous:
                    await websocket.send_json(state)
                    previous = state
                if state["status"] != "active":
                    await websocket.close(1000)
                    return
                try:
                    message = await asyncio.wait_for(websocket.receive(), timeout=1)
                    if message["type"] == "websocket.disconnect":
                        return
                    await websocket.close(1008)
                    return
                except TimeoutError:
                    state = await run_in_threadpool(session_state, db, code)
        except (WebSocketDisconnect, OSError):
            return
